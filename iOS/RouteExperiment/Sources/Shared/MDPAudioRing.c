#include "MDPAudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>

struct MDPAudioRing {
    uint32_t capacity;
    _Atomic(uint64_t) read;
    _Atomic(uint64_t) write;
    float *samples;
};

MDPAudioRing *MDPAudioRingCreate(uint32_t capacityFrames) {
    if (!capacityFrames || (uint64_t)capacityFrames * 2 > SIZE_MAX / sizeof(float)) return NULL;
    MDPAudioRing *ring = calloc(1, sizeof(*ring));
    if (!ring) return NULL;
    atomic_init(&ring->read, 0);
    atomic_init(&ring->write, 0);
    if (!atomic_is_lock_free(&ring->read) || !atomic_is_lock_free(&ring->write)) {
        free(ring);
        return NULL;
    }
    ring->samples = calloc((size_t)capacityFrames * 2, sizeof(float));
    if (!ring->samples) { free(ring); return NULL; }
    ring->capacity = capacityFrames;
    return ring;
}

void MDPAudioRingDestroy(MDPAudioRing *ring) {
    if (ring) { free(ring->samples); free(ring); }
}

uint32_t MDPAudioRingAvailable(const MDPAudioRing *ring) {
    // A third observer can see counters from different instants. Clamp that
    // snapshot rather than reporting an underflow or more than capacity.
    uint64_t read = atomic_load_explicit(&ring->read, memory_order_acquire);
    uint64_t write = atomic_load_explicit(&ring->write, memory_order_acquire);
    if (write < read) return 0;
    uint64_t count = write - read;
    return (uint32_t)(count > ring->capacity ? ring->capacity : count);
}

uint32_t MDPAudioRingWrite(MDPAudioRing *ring, const float *samples,
                           uint32_t frames, uint32_t channels) {
    if (channels != 1 && channels != 2) return 0;
    uint64_t write = atomic_load_explicit(&ring->write, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&ring->read, memory_order_acquire);
    uint64_t occupied = write - read;
    if (occupied > ring->capacity) return 0;
    uint32_t space = ring->capacity - (uint32_t)occupied;
    uint32_t count = frames < space ? frames : space;
    for (uint32_t i = 0; i < count; ++i) {
        size_t dst = (size_t)((write + i) % ring->capacity) * 2;
        size_t src = (size_t)i * channels;
        ring->samples[dst] = samples[src];
        ring->samples[dst + 1] = channels == 2 ? samples[src + 1] : samples[src];
    }
    atomic_store_explicit(&ring->write, write + count, memory_order_release);
    return count;
}

uint32_t MDPAudioRingRead(MDPAudioRing *ring, float *samples, uint32_t frames) {
    uint64_t read = atomic_load_explicit(&ring->read, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&ring->write, memory_order_acquire);
    uint64_t available = write - read;
    if (available > ring->capacity) return 0;
    uint32_t count = available < frames ? (uint32_t)available : frames;
    for (uint32_t i = 0; i < count; ++i) {
        size_t src = (size_t)((read + i) % ring->capacity) * 2;
        samples[(size_t)i * 2] = ring->samples[src];
        samples[(size_t)i * 2 + 1] = ring->samples[src + 1];
    }
    atomic_store_explicit(&ring->read, read + count, memory_order_release);
    return count;
}

void MDPAudioRingDiscard(MDPAudioRing *ring) {
    uint64_t write = atomic_load_explicit(&ring->write, memory_order_acquire);
    atomic_store_explicit(&ring->read, write, memory_order_release);
}
