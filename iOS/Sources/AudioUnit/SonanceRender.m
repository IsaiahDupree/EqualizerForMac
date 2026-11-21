#import "SonanceRender.h"
#import <Accelerate/Accelerate.h>
#import <os/lock.h>
#include <stddef.h>

enum { maxChannels = 2 };

struct SonanceRender {
    os_unfair_lock lock;
    double staged[SonanceRenderCoefficientCount];
    bool hasUpdate;
    bool activeSections[SonanceRenderSections];
    double renderCoefficients[SonanceRenderCoefficientCount * maxChannels];

    vDSP_biquadm_Setup setup;
    AudioBufferList *input;
    float *scratch;
    AUAudioFrameCount maxFrames;
    uint32_t channels;
    double sampleRate;
    SonanceAnalysisCapture *analysis;
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
        for (size_t section = 0; section < SonanceRenderSections; ++section) {
            render->staged[5 * section] = 1;
        }
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
    render->input = NULL;
    render->scratch = NULL;
    render->maxFrames = 0;
    render->channels = 0;
}

void SonanceRenderDestroy(SonanceRender *render) {
    SonanceRenderReleaseResources(render);
    SonanceAnalysisDestroy(render->analysis);
    free(render);
}

SonanceAnalysisCapture *SonanceRenderAnalysis(SonanceRender *render) { return render->analysis; }

void SonanceRenderStage(SonanceRender *render, const double *coefficients) {
    os_unfair_lock_lock(&render->lock);
    memcpy(render->staged, coefficients, sizeof(render->staged));
    render->hasUpdate = true;
    os_unfair_lock_unlock(&render->lock);
}

// vDSP expects section-major coefficients, with one row per channel within each section.
static void expandChannels(double *destination, const double *source, uint32_t channels) {
    for (size_t section = 0; section < SonanceRenderSections; ++section) {
        for (size_t channel = 0; channel < channels; ++channel) {
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
    expandChannels(render->renderCoefficients, render->staged, channels);
    for (size_t section = 0; section < SonanceRenderSections; ++section) {
        render->activeSections[section] = section == 0 || needsFiltering(&render->staged[5 * section]);
    }
    render->hasUpdate = false;
    os_unfair_lock_unlock(&render->lock);

    render->setup = vDSP_biquadm_CreateSetup(render->renderCoefficients, SonanceRenderSections, channels);
    render->input = calloc(1, offsetof(AudioBufferList, mBuffers) + channels * sizeof(AudioBuffer));
    render->scratch = calloc((size_t)maxFrames * channels, sizeof(float));
    if (render->setup == NULL || render->input == NULL || render->scratch == NULL) {
        SonanceRenderReleaseResources(render);
        return false;
    }
    vDSP_biquadm_SetActiveFilters(render->setup, render->activeSections);
    render->channels = channels;
    render->maxFrames = maxFrames;
    render->sampleRate = sampleRate;
    return true;
}

void SonanceRenderReset(SonanceRender *render) {
    if (render->setup != NULL) {
        vDSP_biquadm_ResetState(render->setup);
    }
}

static void applyUpdate(SonanceRender *render) {
    if (!os_unfair_lock_trylock(&render->lock)) {
        return;
    }
    bool changed = render->hasUpdate;
    bool activated = false;
    if (changed) {
        expandChannels(render->renderCoefficients, render->staged, render->channels);
        for (size_t section = 1; section < SonanceRenderSections; ++section) {
            if (!render->activeSections[section] && needsFiltering(&render->staged[5 * section])) {
                render->activeSections[section] = true;
                activated = true;
            }
        }
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
        vDSP_biquadm(render->setup, inputs, 1, outputs, 1, frames);
        SonanceAnalysisPush(render->analysis, outputs[0], channels == 2 ? outputs[1] : NULL, frames, render->sampleRate);
        // The filter can still have a tail when the input is silent.
        *flags &= ~kAudioUnitRenderAction_OutputIsSilence;
        return noErr;
    };
}
