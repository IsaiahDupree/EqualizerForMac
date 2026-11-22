//  LocalLink.m
//  BSD ソケットで書いてある。Network.framework だと拡張側の制約が読みにくいので、
//  拒否が出たときにどのシステムコールかがそのまま分かる形にした。

#import "LocalLink.h"
#import "MDPAudioRing.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <math.h>
#import <string.h>
#import <os/log.h>
#import <stdatomic.h>

static os_log_t MDPLinkLog(void) {
    static os_log_t l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("com.isaiahdupree.SonanceEQ.RouteLab", "link"); });
    return l;
}

// ---- 線の形式 ----
//
// TCP はバイトの列で、4 バイト境界では切れてくれない。recv が返す n が 4 の倍数だと
// 決めつけて n/4 サンプルだけ取ると、余りの 1〜3 バイトが捨てられる。そこから先は
// 隣り合う 2 サンプルにまたがる 4 バイトを float として読むことになり、指数部が
// 任意の値になるので NaN・1e38・非正規化まで飛ぶ。1 回ずれたら復帰しない。
//
// そこで
//   1. 送受とも端数をバイト単位で持ち越す（捨てない・送り直さない）
//   2. チャンクごとにマジックとサンプル数を付け、受け側で毎回検算する
// の両方を持たせた。1 だけだと、ずれたときに誰も気付けない。
//
// 同一機内の 127.0.0.1 しか通らないのでバイト順の変換はしない。送受ともこのファイル。
// 値は 'MDPL1001'。リトルエンディアンで書くので hexdump には "1001KLTE" と並ぶ。
#define MDP_LINK_MAGIC       0x45544c4b31303031ull
#define MDP_LINK_HDR_BYTES   12                      // マジック 8 + サンプル数 4
#define MDP_LINK_MAX_SAMPLES 4096                    // 1 チャンクの上限（2048 フレーム）
#define MDP_LINK_CHUNK_BYTES (MDP_LINK_HDR_BYTES + MDP_LINK_MAX_SAMPLES * sizeof(float))

// ---- 送り手 ----

#define SEND_RING_FRAMES 8192

@implementation MDPLinkSender {
    _Atomic int _fd;
    dispatch_queue_t _q;
    dispatch_source_t _timer;
    MDPAudioRing *_ring;
    _Atomic bool _running;
    _Atomic uint64_t _framesSent;
    _Atomic uint64_t _framesDropped;
    // 送信中のチャンク。_txOff はサンプルではなくバイト位置。
    uint8_t *_txBuf;
    size_t _txLen;
    size_t _txOff;
    uint32_t _txSamples;
}

+ (MDPLinkSender *)shared {
    static MDPLinkSender *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MDPLinkSender alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&_fd, -1);
        atomic_init(&_running, false);
        atomic_init(&_framesSent, 0);
        atomic_init(&_framesDropped, 0);
        _q = dispatch_queue_create("com.isaiahdupree.SonanceEQ.RouteLab.link.send", DISPATCH_QUEUE_SERIAL);
        _ring = MDPAudioRingCreate(SEND_RING_FRAMES);
        // malloc 由来なので先頭は 16 バイト境界。ヘッダ 12 の直後の float 配列も 4 で揃う。
        _txBuf = calloc(1, MDP_LINK_CHUNK_BYTES);
        if (!_ring || !_txBuf) { MDPAudioRingDestroy(_ring); free(_txBuf); return nil; }
    }
    return self;
}

- (BOOL)connected { return _fd >= 0; }
- (uint64_t)sentFrames { return atomic_load(&_framesSent); }
- (uint64_t)droppedFrames { return atomic_load(&_framesDropped); }

- (void)start {
    @synchronized (self) {
    if (_running) return;
    _running = YES;
    dispatch_sync(_q, ^{
        MDPAudioRingDiscard(self->_ring);
        self->_txLen = self->_txOff = 0;
        self->_txSamples = 0;
    });
    // 毎回 0 から数える。累計のままだと、今回何も送っていなくても
    // 「送信=188万」のように見えて、ログで判断を誤る。
    atomic_store(&_framesSent, 0);
    atomic_store(&_framesDropped, 0);
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
    // 10ms ごとに溜まったぶんを送る。接続が無ければ張り直す。
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
    __weak typeof(self) weak = self;
    dispatch_source_set_event_handler(_timer, ^{ [weak pump]; });
    dispatch_resume(_timer);
    os_log_error(MDPLinkLog(), "ET sender 開始");
    }
}

- (void)stop {
    @synchronized (self) {
    _running = NO;
    if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
    dispatch_sync(_q, ^{
        if (self->_fd >= 0) { close(self->_fd); self->_fd = -1; }
        self->_txLen = self->_txOff = 0;
        self->_txSamples = 0;
        MDPAudioRingDiscard(self->_ring);
    });
    os_log(MDPLinkLog(), "sender 停止 sent=%llu", (unsigned long long)self.sentFrames);
    }
}

- (void)pushInterleaved:(const float *)samples frames:(uint32_t)frames channels:(uint32_t)channels {
    if (!_running || !samples || frames == 0) return;
    uint32_t accepted = MDPAudioRingWrite(_ring, samples, frames, channels);
    atomic_fetch_add_explicit(&_framesDropped, frames - accepted, memory_order_relaxed);
}

- (void)ensureConnected {
    if (_fd >= 0) return;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        os_log_error(MDPLinkLog(), "socket 失敗 errno=%d", errno);
        return;
    }
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    // A disappearing receiver must be reported as EPIPE, not kill the extension.
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) {
        os_log_error(MDPLinkLog(), "SO_NOSIGPIPE failed errno=%d", errno);
        close(fd);
        return;
    }

    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(MDP_LINK_PORT);
    inet_pton(AF_INET, MDP_LINK_HOST, &a.sin_addr);

    if (connect(fd, (struct sockaddr *)&a, sizeof(a)) != 0) {
        static int logged = 0;
        if (logged++ < 5) os_log_error(MDPLinkLog(), "MDP connect 失敗 errno=%d", errno);
        close(fd);
        return;
    }
    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    _fd = fd;
    MDPAudioRingDiscard(_ring); // Drop samples accumulated before this connection.
    // 前の接続で送り残したチャンクの途中から流すと、新しいストリームの先頭が
    // ヘッダにならない。持ち越しはここで捨てる。
    _txLen = _txOff = 0;
    _txSamples = 0;
    os_log_error(MDPLinkLog(), "MDP connect 成功 port=%d", MDP_LINK_PORT);
}

/// 送信中のチャンクの残りを吐き出す。全部出せたら YES。
/// 端数で止まったら _txOff にバイト位置を残して NO を返す。
/// send が返すのはバイト数で、float の途中で止まりうる。ここをサンプル単位で
/// 数えると端数バイトは送信済みなのに読み位置が戻り、同じサンプルの先頭を
/// 送り直す＝受け側が 1〜3 バイトずれる。だからバイトで数える。
- (BOOL)flushPending {
    while (_txOff < _txLen) {
        ssize_t sent = send(_fd, _txBuf + _txOff, _txLen - _txOff, 0);
        if (sent > 0) { _txOff += (size_t)sent; continue; }
        if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return NO;
        os_log_error(MDPLinkLog(), "send 失敗 errno=%d", errno);
        close(_fd); _fd = -1;
        _txLen = _txOff = 0;
        _txSamples = 0;
        return NO;
    }
    // 送り切ったチャンクだけ数える。途中で止まったぶんは次の pump で数える。
    if (_txSamples) { atomic_fetch_add(&_framesSent, _txSamples / 2); _txSamples = 0; }
    return YES;
}

- (void)pump {
    if (!_running) return;
    [self ensureConnected];
    if (_fd < 0) return;

    if (![self flushPending]) return;   // 前回の残りが先

    // Bound each timer invocation so a fast producer cannot monopolize the queue.
    for (int pass = 0; pass < 8; ++pass) {
        float *payload = (float *)(void *)(_txBuf + MDP_LINK_HDR_BYTES);
        uint32_t frames = MDPAudioRingRead(_ring, payload, MDP_LINK_MAX_SAMPLES / 2);
        if (!frames) return;
        uint32_t n = frames * 2;

        uint64_t magic = MDP_LINK_MAGIC;
        uint32_t count = n;
        memcpy(_txBuf, &magic, sizeof(magic));
        memcpy(_txBuf + 8, &count, sizeof(count));

        _txLen = MDP_LINK_HDR_BYTES + (size_t)n * sizeof(float);
        _txOff = 0;
        _txSamples = n;

        // リングから _txBuf へ写した時点で読み位置を進める。送信が途中で止まっても
        // 残りは _txBuf が持っているので、リングを読み直す必要は無い。
        if (![self flushPending]) return;   // 続きは次の pump
    }
}

@end

// ---- 受け手 ----

#define RECV_RING_FRAMES 8192
#define RX_BUF_BYTES      65536     // 1 チャンク（最大 16396 バイト）より十分大きく取る

@implementation MDPLinkReceiver {
    _Atomic int _listenFd;
    _Atomic int _peerFd;
    dispatch_queue_t _q;
    dispatch_source_t _timer;
    MDPAudioRing *_ring;
    _Atomic uint64_t _framesReceived;
    _Atomic uint64_t _framesDropped;
    _Atomic uint64_t _framesUnderrun;
    _Atomic uint64_t _generation;
    uint64_t _consumerGeneration; // accessed by the audio consumer only
    // 受信したバイトをそのまま溜める。float に切り出すのは境界が揃ってから。
    uint8_t *_rxBuf;
    size_t _rxLen;
    uint64_t _badSamples;
}

+ (MDPLinkReceiver *)shared {
    static MDPLinkReceiver *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MDPLinkReceiver alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&_listenFd, -1);
        atomic_init(&_peerFd, -1);
        atomic_init(&_framesReceived, 0);
        atomic_init(&_framesDropped, 0);
        atomic_init(&_framesUnderrun, 0);
        atomic_init(&_generation, 0);
        _q = dispatch_queue_create("com.isaiahdupree.SonanceEQ.RouteLab.link.recv", DISPATCH_QUEUE_SERIAL);
        _ring = MDPAudioRingCreate(RECV_RING_FRAMES);
        _rxBuf = calloc(1, RX_BUF_BYTES);
        if (!_ring || !_rxBuf) { MDPAudioRingDestroy(_ring); free(_rxBuf); return nil; }
    }
    return self;
}

- (BOOL)listening { return _listenFd >= 0; }
- (BOOL)hasPeer   { return _peerFd >= 0; }
- (uint64_t)receivedFrames { return atomic_load(&_framesReceived); }
- (uint64_t)droppedFrames { return atomic_load(&_framesDropped); }
- (uint64_t)underrunFrames { return atomic_load(&_framesUnderrun); }

- (uint32_t)bufferedFrames {
    return MDPAudioRingAvailable(_ring);
}

- (BOOL)start {
    @synchronized (self) {
    if (_listenFd >= 0) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        os_log_error(MDPLinkLog(), "receiver socket 失敗 errno=%d", errno);
        return NO;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(MDP_LINK_PORT);
    inet_pton(AF_INET, MDP_LINK_HOST, &a.sin_addr);

    if (bind(fd, (struct sockaddr *)&a, sizeof(a)) != 0) {
        os_log_error(MDPLinkLog(), "bind 失敗 errno=%d", errno);
        close(fd);
        return NO;
    }
    if (listen(fd, 1) != 0) {
        os_log_error(MDPLinkLog(), "listen 失敗 errno=%d", errno);
        close(fd);
        return NO;
    }
    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    _listenFd = fd;
    _rxLen = 0;
    atomic_fetch_add(&_generation, 1);
    atomic_store(&_framesReceived, 0);
    atomic_store(&_framesDropped, 0);
    atomic_store(&_framesUnderrun, 0);
    os_log_error(MDPLinkLog(), "MDP receiver 待ち受け開始 port=%d", MDP_LINK_PORT);

    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC, 1 * NSEC_PER_MSEC);
    __weak typeof(self) weak = self;
    dispatch_source_set_event_handler(_timer, ^{ [weak pump]; });
    dispatch_resume(_timer);
    return YES;
    }
}

- (void)stop {
    @synchronized (self) {
    if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
    dispatch_sync(_q, ^{
        if (self->_peerFd >= 0) { close(self->_peerFd); self->_peerFd = -1; }
        if (self->_listenFd >= 0) { close(self->_listenFd); self->_listenFd = -1; }
        self->_rxLen = 0;
        atomic_fetch_add(&self->_generation, 1);
    });
    }
}

/// チャンク本体をリングへ写す。
- (void)writeSamples:(const uint8_t *)bytes count:(uint32_t)count {
    uint64_t badBefore = _badSamples;
    float decoded[MDP_LINK_MAX_SAMPLES];
    for (uint32_t i = 0; i < count; i++) {
        float v;
        // _rxBuf の途中から読むので 4 バイト境界に乗っている保証が無い。memcpy で取る。
        memcpy(&v, bytes + (size_t)i * sizeof(float), sizeof(v));
        // NaN や inf を 1 つ通すと IIR の状態が戻らなくなり、以後ずっと無音か轟音になる。
        // ここで落として数を記録する（黙って埋めると原因が見えない）。
        if (!isfinite(v)) { v = 0.0f; _badSamples++; }
        decoded[i] = v;
    }
    uint32_t frames = count / 2;
    uint32_t accepted = MDPAudioRingWrite(_ring, decoded, frames, 2);
    atomic_fetch_add_explicit(&_framesReceived, frames, memory_order_relaxed);
    atomic_fetch_add_explicit(&_framesDropped, frames - accepted, memory_order_relaxed);

    // ここで出さないと、同期ずれを伴わない非有限値（送り手側で既に壊れている音）が
    // 黙って 0 に置き換わる。consume 側の bad= は同期ずれが起きたときしか通らない。
    if (_badSamples > badBefore) {
        static int logged = 0;
        if (logged++ < 20) {
            os_log_error(MDPLinkLog(), "ET 非有限値 %llu 個を 0 にした 累計=%llu",
                         (unsigned long long)(_badSamples - badBefore),
                         (unsigned long long)_badSamples);
        }
    }
}

/// 溜めたバイト列から取り出せるチャンクを全部取り出し、残りを先頭へ寄せる。
/// ヘッダが揃わない端数・本体が届いていないチャンクはそのまま次の recv へ持ち越す。
- (void)consume {
    size_t off = 0;
    size_t skipped = 0;
    while (_rxLen - off >= MDP_LINK_HDR_BYTES) {
        uint64_t magic = 0;
        uint32_t count = 0;
        memcpy(&magic, _rxBuf + off, sizeof(magic));
        memcpy(&count, _rxBuf + off + 8, sizeof(count));
        // 送り側が必ず偶数サンプルで切るので、奇数はずれている証拠として弾く。
        if (magic != MDP_LINK_MAGIC || count == 0 || (count & 1u) || count > MDP_LINK_MAX_SAMPLES) {
            off += 1;       // 1 バイトずつずらして次のマジックを探す
            skipped++;
            continue;
        }
        size_t need = MDP_LINK_HDR_BYTES + (size_t)count * sizeof(float);
        if (_rxLen - off < need) break;     // 本体がまだ揃っていない
        [self writeSamples:_rxBuf + off + MDP_LINK_HDR_BYTES count:count];
        off += need;
    }
    if (off > 0) {
        memmove(_rxBuf, _rxBuf + off, _rxLen - off);
        _rxLen -= off;
    }
    if (skipped > 0) {
        static int logged = 0;
        if (logged++ < 20) {
            os_log_error(MDPLinkLog(), "ET 同期ずれ %zu バイト読み飛ばし bad=%llu",
                         skipped, (unsigned long long)_badSamples);
        }
    }
}

- (void)pump {
    if (_listenFd < 0) return;
    if (_peerFd < 0) {
        int c = accept(_listenFd, NULL, NULL);
        if (c >= 0) {
            int fl = fcntl(c, F_GETFL, 0);
            fcntl(c, F_SETFL, fl | O_NONBLOCK);
            _peerFd = c;
            _rxLen = 0;     // 前の相手の書きかけを新しいストリームに混ぜない
            atomic_fetch_add(&_generation, 1);
            os_log_error(MDPLinkLog(), "ET 接続を受けた");
        }
        return;
    }
    for (int pass = 0; pass < 8; pass++) {
        // consume の後は必ず 1 チャンク未満しか残らないので空きはあるが、
        // 長さ 0 の recv は戻り値 0（＝切断）と区別できないので念のため止める。
        if (_rxLen >= RX_BUF_BYTES) return;
        ssize_t n = recv(_peerFd, _rxBuf + _rxLen, RX_BUF_BYTES - _rxLen, 0);
        if (n == 0) {
            os_log(MDPLinkLog(), "相手が切断した");
            close(_peerFd); _peerFd = -1;
            _rxLen = 0;
            atomic_fetch_add(&_generation, 1);
            return;
        }
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) return;
            os_log_error(MDPLinkLog(), "recv 失敗 errno=%d", errno);
            close(_peerFd); _peerFd = -1;
            _rxLen = 0;
            atomic_fetch_add(&_generation, 1);
            return;
        }
        // n は 4 の倍数とは限らない。端数は _rxBuf に残したまま次の recv と繋ぐ。
        _rxLen += (size_t)n;
        [self consume];
    }
}

- (uint32_t)readInterleaved:(float *)out frames:(uint32_t)frames {
    if (!out) return 0;
    uint64_t generation = atomic_load_explicit(&_generation, memory_order_acquire);
    if (_consumerGeneration != generation) {
        MDPAudioRingDiscard(_ring);
        _consumerGeneration = generation;
    }
    uint32_t got = MDPAudioRingRead(_ring, out, frames);
    // If the connection changed during the read, do not render the old block.
    if (generation != atomic_load_explicit(&_generation, memory_order_acquire)) got = 0;
    atomic_fetch_add_explicit(&_framesUnderrun, frames - got, memory_order_relaxed);
    for (size_t i = (size_t)got * 2; i < (size_t)frames * 2; ++i) out[i] = 0.0f;
    return got;
}

@end
