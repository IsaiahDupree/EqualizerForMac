#pragma once
#include <stdint.h>

// A bounded stereo-frame queue. Exactly one producer may write and exactly
// one consumer may read or discard. Status observers may call Available.
typedef struct MDPAudioRing MDPAudioRing;
MDPAudioRing * _Nullable MDPAudioRingCreate(uint32_t capacityFrames);
void MDPAudioRingDestroy(MDPAudioRing * _Nullable ring);
uint32_t MDPAudioRingAvailable(const MDPAudioRing * _Nonnull ring);
uint32_t MDPAudioRingWrite(MDPAudioRing * _Nonnull ring, const float * _Nonnull samples,
                           uint32_t frames, uint32_t channels);
uint32_t MDPAudioRingRead(MDPAudioRing * _Nonnull ring, float * _Nonnull samples, uint32_t frames);
void MDPAudioRingDiscard(MDPAudioRing * _Nonnull ring);
