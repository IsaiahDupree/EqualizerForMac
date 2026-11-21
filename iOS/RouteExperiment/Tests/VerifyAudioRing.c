#include "MDPAudioRing.h"
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>

enum { framesToTransfer = 100000 };
typedef struct { MDPAudioRing *ring; int error; } Context;

static void *produce(void *arg) {
    Context *context = arg;
    for (int n = 1; n <= framesToTransfer; ++n) {
        float frame[] = { (float)n, (float)-n };
        while (MDPAudioRingWrite(context->ring, frame, 1, 2) == 0) sched_yield();
    }
    return NULL;
}

static void *consume(void *arg) {
    Context *context = arg;
    for (int n = 1; n <= framesToTransfer; ++n) {
        float frame[2];
        while (MDPAudioRingRead(context->ring, frame, 1) == 0) sched_yield();
        if (frame[0] != (float)n || frame[1] != (float)-n) context->error = 1;
    }
    return NULL;
}

int main(void) {
    assert(MDPAudioRingCreate(0) == NULL);
    MDPAudioRing *ring = MDPAudioRingCreate(3);
    assert(ring);
    float mono[] = { 1, 2, 3, 4 }, out[8] = { 0 };
    assert(MDPAudioRingWrite(ring, mono, 4, 1) == 3);
    assert(MDPAudioRingAvailable(ring) == 3);
    assert(MDPAudioRingRead(ring, out, 2) == 2);
    assert(out[0] == 1 && out[1] == 1 && out[2] == 2 && out[3] == 2);
    assert(MDPAudioRingWrite(ring, mono + 3, 1, 1) == 1);
    assert(MDPAudioRingRead(ring, out, 3) == 2);
    assert(out[0] == 3 && out[1] == 3 && out[2] == 4 && out[3] == 4);
    assert(MDPAudioRingWrite(ring, mono, 3, 1) == 3);
    MDPAudioRingDiscard(ring);
    assert(MDPAudioRingAvailable(ring) == 0);
    MDPAudioRingDestroy(ring);

    ring = MDPAudioRingCreate(64);
    assert(ring);
    Context context = { .ring = ring, .error = 0 };
    pthread_t writer, reader;
    assert(pthread_create(&writer, NULL, produce, &context) == 0);
    assert(pthread_create(&reader, NULL, consume, &context) == 0);
    assert(pthread_join(writer, NULL) == 0);
    assert(pthread_join(reader, NULL) == 0);
    assert(!context.error && MDPAudioRingAvailable(ring) == 0);
    MDPAudioRingDestroy(ring);
    puts("PASS: ring capacity, wrap, mono, discard and 100000 concurrent stereo frames");
    return 0;
}
