#import "SonanceRender.h"
#import <Accelerate/Accelerate.h>
#import <mach/mach_time.h>
#import <os/lock.h>
#include <stddef.h>
#include <stdatomic.h>

enum { maxChannels = 2 };

struct SonanceRender {
    os_unfair_lock lock;
    double staged[SonanceRenderCoefficientCount];
    double stagedSide[SonanceRenderCoefficientCount];
    bool hasUpdate;
    bool stagedMidSide;
    bool renderMidSide;
    bool stagedLinearPhase;
    bool renderLinearPhase;
    float stagedMidFIR[SonanceFIRLength];
    float stagedSideFIR[SonanceFIRLength];
    float renderMidFIR[SonanceFIRLength];
    float renderSideFIR[SonanceFIRLength];
    bool activeSections[SonanceRenderSections];
    double renderCoefficients[SonanceRenderCoefficientCount * maxChannels];

    vDSP_biquadm_Setup setup;
    AudioBufferList *input;
    float *scratch;
    float *midSideScratch;
    float *firHistory;
    float *firInput;
    float *firOutput;
    AUAudioFrameCount maxFrames;
    uint32_t channels;
    double sampleRate;
    SonanceAnalysisCapture *analysis;
    mach_timebase_info_data_t timebase;
    atomic_uint_fast64_t completedBlocks;
    atomic_uint_fast64_t deadlineMisses;
    atomic_uint_fast64_t maximumProcessingNanoseconds;
    atomic_uint_fast64_t lastDeadlineNanoseconds;
};

SonanceRender *SonanceRenderCreate(void) {
    SonanceRender *render = calloc(1, sizeof(*render));
    if (render != NULL) {
        render->analysis = SonanceAnalysisCreate();
        if (render->analysis == NULL) {
            free(render);
            return NULL;
        }
        render->lock = OS_UNFAIR_LOCK_INIT;
        mach_timebase_info(&render->timebase);
        atomic_init(&render->completedBlocks, 0);
        atomic_init(&render->deadlineMisses, 0);
        atomic_init(&render->maximumProcessingNanoseconds, 0);
        atomic_init(&render->lastDeadlineNanoseconds, 0);
        if (!atomic_is_lock_free(&render->completedBlocks)) {
            SonanceAnalysisDestroy(render->analysis);
            free(render);
            return NULL;
        }
        for (size_t section = 0; section < SonanceRenderSections; ++section) {
            render->staged[5 * section] = 1;
            render->stagedSide[5 * section] = 1;
        }
        render->stagedMidFIR[(SonanceFIRLength - 1) / 2] = 1;
        render->stagedSideFIR[(SonanceFIRLength - 1) / 2] = 1;
        render->renderMidFIR[(SonanceFIRLength - 1) / 2] = 1;
        render->renderSideFIR[(SonanceFIRLength - 1) / 2] = 1;
    }
    return render;
}

void SonanceRenderReleaseResources(SonanceRender *render) {
    if (render->setup != NULL) {
        vDSP_biquadm_DestroySetup(render->setup);
        render->setup = NULL;
    }
    free(render->input);
    free(render->scratch);
    free(render->midSideScratch);
    free(render->firHistory);
    free(render->firInput);
    free(render->firOutput);
    render->input = NULL;
    render->scratch = NULL;
    render->midSideScratch = NULL;
    render->firHistory = NULL;
    render->firInput = NULL;
    render->firOutput = NULL;
    render->maxFrames = 0;
    render->channels = 0;
}

void SonanceRenderDestroy(SonanceRender *render) {
    SonanceRenderReleaseResources(render);
    SonanceAnalysisDestroy(render->analysis);
    free(render);
}

SonanceAnalysisCapture *SonanceRenderAnalysis(SonanceRender *render) { return render->analysis; }
uint64_t SonanceRenderCompletedBlocks(SonanceRender *render) {
    return atomic_load_explicit(&render->completedBlocks, memory_order_relaxed);
}
uint64_t SonanceRenderDeadlineMisses(SonanceRender *render) {
    return atomic_load_explicit(&render->deadlineMisses, memory_order_relaxed);
}
uint64_t SonanceRenderMaximumProcessingNanoseconds(SonanceRender *render) {
    return atomic_load_explicit(&render->maximumProcessingNanoseconds, memory_order_relaxed);
}
uint64_t SonanceRenderLastDeadlineNanoseconds(SonanceRender *render) {
    return atomic_load_explicit(&render->lastDeadlineNanoseconds, memory_order_relaxed);
}

void SonanceRenderStage(SonanceRender *render, const double *midCoefficients,
                        const double *sideCoefficients, bool midSideEnabled,
                        const float *midFIR, const float *sideFIR, bool linearPhaseEnabled) {
    os_unfair_lock_lock(&render->lock);
    memcpy(render->staged, midCoefficients, sizeof(render->staged));
    memcpy(render->stagedSide, sideCoefficients, sizeof(render->stagedSide));
    render->stagedMidSide = midSideEnabled;
    memcpy(render->stagedMidFIR, midFIR, sizeof(render->stagedMidFIR));
    memcpy(render->stagedSideFIR, sideFIR, sizeof(render->stagedSideFIR));
    render->stagedLinearPhase = linearPhaseEnabled;
    render->hasUpdate = true;
    os_unfair_lock_unlock(&render->lock);
}

// vDSP expects section-major coefficients, with one row per channel within each section.
static void expandChannels(double *destination, const double *mid, const double *side,
                           uint32_t channels, bool midSideEnabled) {
    for (size_t section = 0; section < SonanceRenderSections; ++section) {
        for (size_t channel = 0; channel < channels; ++channel) {
            const double *source = midSideEnabled && channel == 1 ? side : mid;
            memcpy(destination + 5 * (section * channels + channel), source + 5 * section, 5 * sizeof(double));
        }
    }
}

static bool needsFiltering(const double *section) {
    return section[0] != 1 || section[1] != 0 || section[2] != 0 || section[3] != 0 || section[4] != 0;
}

bool SonanceRenderPrepare(SonanceRender *render, AUAudioFrameCount maxFrames, uint32_t channels, double sampleRate) {
    SonanceRenderReleaseResources(render);
    if (channels == 0 || channels > maxChannels || maxFrames == 0 || maxFrames > UINT32_MAX / sizeof(float)) {
        return false;
    }

    os_unfair_lock_lock(&render->lock);
    expandChannels(render->renderCoefficients, render->staged, render->stagedSide, channels, render->stagedMidSide);
    for (size_t section = 0; section < SonanceRenderSections; ++section) {
        render->activeSections[section] = section == 0 || needsFiltering(&render->staged[5 * section]) ||
            (render->stagedMidSide && channels > 1 && needsFiltering(&render->stagedSide[5 * section]));
    }
    render->renderMidSide = render->stagedMidSide;
    memcpy(render->renderMidFIR, render->stagedMidFIR, sizeof(render->renderMidFIR));
    memcpy(render->renderSideFIR, render->stagedSideFIR, sizeof(render->renderSideFIR));
    render->renderLinearPhase = render->stagedLinearPhase;
    render->hasUpdate = false;
    os_unfair_lock_unlock(&render->lock);

    render->setup = vDSP_biquadm_CreateSetup(render->renderCoefficients, SonanceRenderSections, channels);
    render->input = calloc(1, offsetof(AudioBufferList, mBuffers) + channels * sizeof(AudioBuffer));
    render->scratch = calloc((size_t)maxFrames * channels, sizeof(float));
    render->midSideScratch = calloc((size_t)maxFrames * channels, sizeof(float));
    const size_t historyLength = SonanceFIRLength - 1;
    render->firHistory = calloc((size_t)channels * historyLength, sizeof(float));
    render->firInput = calloc((size_t)maxFrames + historyLength, sizeof(float));
    render->firOutput = calloc((size_t)maxFrames, sizeof(float));
    if (render->setup == NULL || render->input == NULL || render->scratch == NULL || render->midSideScratch == NULL ||
        render->firHistory == NULL || render->firInput == NULL || render->firOutput == NULL) {
        SonanceRenderReleaseResources(render);
        return false;
    }
    vDSP_biquadm_SetActiveFilters(render->setup, render->activeSections);
    render->channels = channels;
    render->maxFrames = maxFrames;
    render->sampleRate = sampleRate;
    atomic_store_explicit(&render->completedBlocks, 0, memory_order_relaxed);
    atomic_store_explicit(&render->deadlineMisses, 0, memory_order_relaxed);
    atomic_store_explicit(&render->maximumProcessingNanoseconds, 0, memory_order_relaxed);
    atomic_store_explicit(&render->lastDeadlineNanoseconds, 0, memory_order_relaxed);
    return true;
}

void SonanceRenderReset(SonanceRender *render) {
    if (render->setup != NULL) {
        vDSP_biquadm_ResetState(render->setup);
    }
    if (render->firHistory != NULL) {
        memset(render->firHistory, 0, (size_t)render->channels * (SonanceFIRLength - 1) * sizeof(float));
    }
}

static void processFIR(SonanceRender *render, uint32_t channel, const float *input,
                       float *output, AUAudioFrameCount frames) {
    const size_t historyLength = SonanceFIRLength - 1;
    float *history = render->firHistory + (size_t)channel * historyLength;
    const float *filter = (channel % 2 == 0) ? render->renderMidFIR : render->renderSideFIR;
    memcpy(render->firInput, history, historyLength * sizeof(float));
    memcpy(render->firInput + historyLength, input, (size_t)frames * sizeof(float));
    // The designed FIR is symmetric, so vDSP_conv's correlation orientation is equivalent to convolution.
    vDSP_conv(render->firInput, 1, filter, 1, render->firOutput, 1,
              (vDSP_Length)frames, SonanceFIRLength);
    memcpy(output, render->firOutput, (size_t)frames * sizeof(float));
    memcpy(history, render->firInput + frames, historyLength * sizeof(float));
}

static void rememberFIRHistory(SonanceRender *render, uint32_t channel, const float *input,
                               AUAudioFrameCount frames) {
    const size_t historyLength = SonanceFIRLength - 1;
    float *history = render->firHistory + (size_t)channel * historyLength;
    if (frames >= historyLength) {
        memcpy(history, input + frames - historyLength, historyLength * sizeof(float));
        return;
    }
    memmove(history, history + frames, (historyLength - frames) * sizeof(float));
    memcpy(history + historyLength - frames, input, (size_t)frames * sizeof(float));
}

static void applyUpdate(SonanceRender *render) {
    if (!os_unfair_lock_trylock(&render->lock)) {
        return;
    }
    bool changed = render->hasUpdate;
    bool activated = false;
    if (changed) {
        const bool previousMidSide = render->renderMidSide;
        expandChannels(render->renderCoefficients, render->staged, render->stagedSide,
                       render->channels, render->stagedMidSide);
        for (size_t section = 1; section < SonanceRenderSections; ++section) {
            if (!render->activeSections[section] && (needsFiltering(&render->staged[5 * section]) ||
                (render->stagedMidSide && render->channels > 1 && needsFiltering(&render->stagedSide[5 * section])))) {
                render->activeSections[section] = true;
                activated = true;
            }
        }
        if (previousMidSide != render->stagedMidSide && render->channels == 2 && render->firHistory != NULL) {
            const size_t historyLength = SonanceFIRLength - 1;
            float *first = render->firHistory;
            float *second = first + historyLength;
            for (size_t i = 0; i < historyLength; ++i) {
                const float a = first[i], b = second[i];
                first[i] = render->stagedMidSide ? 0.5f * (a + b) : a + b;
                second[i] = render->stagedMidSide ? 0.5f * (a - b) : a - b;
            }
        }
        render->renderMidSide = render->stagedMidSide;
        memcpy(render->renderMidFIR, render->stagedMidFIR, sizeof(render->renderMidFIR));
        memcpy(render->renderSideFIR, render->stagedSideFIR, sizeof(render->renderSideFIR));
        render->renderLinearPhase = render->stagedLinearPhase;
        render->hasUpdate = false;
    }
    os_unfair_lock_unlock(&render->lock);
    if (changed) {
        vDSP_biquadm_SetTargetsDouble(render->setup, render->renderCoefficients, 0.005f, 1e-7f,
                                      0, 0, SonanceRenderSections, render->channels);
        // Previously used sections keep rendering through their ramp back to unity.
        if (activated) { vDSP_biquadm_SetActiveFilters(render->setup, render->activeSections); }
    }
}

AUInternalRenderBlock SonanceRenderMakeBlock(SonanceRender *render) {
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp,
                              AUAudioFrameCount frames, NSInteger bus, AudioBufferList *output,
                              const AURenderEvent *events, AURenderPullInputBlock pullInput) {
        if (bus != 0) { return kAudioUnitErr_InvalidElement; }
        if (render->setup == NULL) { return kAudioUnitErr_Uninitialized; }
        if (frames > render->maxFrames) { return kAudioUnitErr_TooManyFramesToProcess; }
        if (frames == 0) { return noErr; }
        if (pullInput == nil) { return kAudioUnitErr_NoConnection; }

        const uint32_t channels = render->channels;
        const uint32_t bytes = frames * sizeof(float);
        AudioBufferList *input = render->input;
        if (output->mNumberBuffers != channels) { return kAudioUnitErr_FormatNotSupported; }
        input->mNumberBuffers = channels;
        for (uint32_t channel = 0; channel < channels; ++channel) {
            AudioBuffer destination = output->mBuffers[channel];
            if (destination.mNumberChannels != 1 || (destination.mData && destination.mDataByteSize < bytes)) {
                return kAudioUnitErr_FormatNotSupported;
            }
            input->mBuffers[channel] = (AudioBuffer){1, bytes, render->scratch + (size_t)channel * render->maxFrames};
        }

        AudioUnitRenderActionFlags inputFlags = *flags & ~kAudioUnitRenderAction_OutputIsSilence;
        AUAudioUnitStatus status = pullInput(&inputFlags, timestamp, frames, 0, input);
        if (status != noErr) { return status; }
        if (input->mNumberBuffers != channels) { return kAudioUnitErr_FormatNotSupported; }
        const uint64_t processingStart = mach_absolute_time();

        const float *inputs[maxChannels];
        float *outputs[maxChannels];
        for (uint32_t channel = 0; channel < channels; ++channel) {
            AudioBuffer source = input->mBuffers[channel];
            float *scratch = render->scratch + (size_t)channel * render->maxFrames;
            if (inputFlags & kAudioUnitRenderAction_OutputIsSilence) {
                memset(scratch, 0, bytes);
                inputs[channel] = scratch;
            } else {
                if (source.mNumberChannels != 1 || source.mData == NULL || source.mDataByteSize < bytes) {
                    return kAudioUnitErr_FormatNotSupported;
                }
                inputs[channel] = source.mData;
            }
            outputs[channel] = output->mBuffers[channel].mData ?: scratch;
            output->mBuffers[channel].mData = outputs[channel];
            output->mBuffers[channel].mDataByteSize = bytes;
        }

        applyUpdate(render);
        if (render->renderMidSide && channels == 2) {
            float *left = render->midSideScratch;
            float *right = render->midSideScratch + render->maxFrames;
            for (AUAudioFrameCount frame = 0; frame < frames; ++frame) {
                const float l = inputs[0][frame], r = inputs[1][frame];
                left[frame] = 0.5f * (l + r);
                right[frame] = 0.5f * (l - r);
            }
            inputs[0] = left;
            inputs[1] = right;
        }
        if (render->renderLinearPhase) {
            for (uint32_t channel = 0; channel < channels; ++channel) {
                processFIR(render, channel, inputs[channel], outputs[channel], frames);
            }
        } else {
            vDSP_biquadm(render->setup, inputs, 1, outputs, 1, frames);
            // Keep the FIR's input history current while IIR is selected so switching modes
            // does not start the linear-phase path with an artificial zero-filled window.
            for (uint32_t channel = 0; channel < channels; ++channel) {
                rememberFIRHistory(render, channel, inputs[channel], frames);
            }
        }
        if (render->renderMidSide && channels == 2) {
            for (AUAudioFrameCount frame = 0; frame < frames; ++frame) {
                const float mid = outputs[0][frame], side = outputs[1][frame];
                outputs[0][frame] = mid + side;
                outputs[1][frame] = mid - side;
            }
        }
        SonanceAnalysisPush(render->analysis, outputs[0], channels == 2 ? outputs[1] : NULL, frames, render->sampleRate);
        const uint64_t elapsedTicks = mach_absolute_time() - processingStart;
        const uint64_t elapsedNanoseconds = elapsedTicks * render->timebase.numer / render->timebase.denom;
        const uint64_t deadlineNanoseconds = (uint64_t)((double)frames * 1000000000.0 / render->sampleRate);
        atomic_fetch_add_explicit(&render->completedBlocks, 1, memory_order_relaxed);
        atomic_store_explicit(&render->lastDeadlineNanoseconds, deadlineNanoseconds, memory_order_relaxed);
        if (elapsedNanoseconds > deadlineNanoseconds) {
            atomic_fetch_add_explicit(&render->deadlineMisses, 1, memory_order_relaxed);
        }
        uint64_t maximum = atomic_load_explicit(&render->maximumProcessingNanoseconds, memory_order_relaxed);
        while (elapsedNanoseconds > maximum &&
               !atomic_compare_exchange_weak_explicit(&render->maximumProcessingNanoseconds, &maximum,
                                                       elapsedNanoseconds, memory_order_relaxed,
                                                       memory_order_relaxed)) { }
        // The filter can still have a tail when the input is silent.
        *flags &= ~kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    };
}
