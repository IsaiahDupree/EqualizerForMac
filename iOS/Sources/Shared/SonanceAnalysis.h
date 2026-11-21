#include <stdbool.h>
#include <stdint.h>

#ifndef SonanceAnalysis_h
#define SonanceAnalysis_h

enum { SonanceAnalysisFrameCount = 2048 };
typedef struct SonanceAnalysisCapture SonanceAnalysisCapture;

typedef struct {
    double sampleRate;
    uint32_t channelCount;
} SonanceAnalysisInfo;

SonanceAnalysisCapture *_Nullable SonanceAnalysisCreate(void);
void SonanceAnalysisDestroy(SonanceAnalysisCapture *_Nonnull capture);
void SonanceAnalysisRequest(SonanceAnalysisCapture *_Nonnull capture);
void SonanceAnalysisPush(SonanceAnalysisCapture *_Nonnull capture, const float *_Nonnull left, const float *_Nullable right,
                         uint32_t frames, double sampleRate);
bool SonanceAnalysisRead(SonanceAnalysisCapture *_Nonnull capture, float *_Nonnull left, float *_Nonnull right,
                         SonanceAnalysisInfo *_Nonnull info);

#endif
