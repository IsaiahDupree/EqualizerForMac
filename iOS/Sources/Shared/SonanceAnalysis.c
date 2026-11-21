#include "SonanceAnalysis.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

enum CaptureState { idle, requested, filling, ready, reading };

// The render callback owns the window from requested through filling.
// The reader takes ownership only after the full window has been published.
struct SonanceAnalysisCapture {
    atomic_uint state;
    uint32_t used;
    SonanceAnalysisInfo info;
    float left[SonanceAnalysisFrameCount];
    float right[SonanceAnalysisFrameCount];
};

SonanceAnalysisCapture *SonanceAnalysisCreate(void) {
    SonanceAnalysisCapture *capture = calloc(1, sizeof(*capture));
    if (capture != NULL) { atomic_init(&capture->state, idle); }
    return capture;
}

void SonanceAnalysisDestroy(SonanceAnalysisCapture *capture) {
    free(capture);
}

void SonanceAnalysisRequest(SonanceAnalysisCapture *capture) {
    unsigned expected = idle;
    atomic_compare_exchange_strong_explicit(&capture->state, &expected, requested,
                                            memory_order_release, memory_order_relaxed);
}

void SonanceAnalysisPush(SonanceAnalysisCapture *capture, const float *left, const float *right,
                         uint32_t frames, double sampleRate) {
    unsigned state = atomic_load_explicit(&capture->state, memory_order_acquire);
    if (state != requested && state != filling) { return; }
    const uint32_t channels = right == NULL ? 1 : 2;
    if (state == requested || sampleRate != capture->info.sampleRate || channels != capture->info.channelCount) {
        capture->used = 0;
        capture->info = (SonanceAnalysisInfo){sampleRate, channels};
        atomic_store_explicit(&capture->state, filling, memory_order_relaxed);
    }
    const uint32_t remaining = SonanceAnalysisFrameCount - capture->used;
    const uint32_t count = frames < remaining ? frames : remaining;
    memcpy(capture->left + capture->used, left, count * sizeof(float));
    if (right != NULL) { memcpy(capture->right + capture->used, right, count * sizeof(float)); }
    capture->used += count;
    if (capture->used == SonanceAnalysisFrameCount) {
        atomic_store_explicit(&capture->state, ready, memory_order_release);
    }
}

bool SonanceAnalysisRead(SonanceAnalysisCapture *capture, float *left, float *right, SonanceAnalysisInfo *info) {
    unsigned expected = ready;
    if (!atomic_compare_exchange_strong_explicit(&capture->state, &expected, reading,
                                                 memory_order_acquire, memory_order_relaxed)) {
        return false;
    }
    *info = capture->info;
    memcpy(left, capture->left, sizeof(capture->left));
    if (info->channelCount == 2) { memcpy(right, capture->right, sizeof(capture->right)); }
    atomic_store_explicit(&capture->state, idle, memory_order_release);
    return true;
}
