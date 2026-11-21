#import <AudioToolbox/AUAudioUnitImplementation.h>
#import "../Shared/SonanceAnalysis.h"

NS_ASSUME_NONNULL_BEGIN

// Each filter slot reserves enough sections for a 96 dB/oct cut.
enum { SonanceRenderBands = 32, SonanceSectionsPerBand = 8,
       SonanceRenderSections = SonanceRenderBands * SonanceSectionsPerBand,
       SonanceRenderCoefficientCount = 5 * SonanceRenderSections };

typedef struct SonanceRender SonanceRender;

SonanceRender *_Nullable SonanceRenderCreate(void);
void SonanceRenderDestroy(SonanceRender *render);
void SonanceRenderStage(SonanceRender *render, const double *coefficients);
bool SonanceRenderPrepare(SonanceRender *render, AUAudioFrameCount maxFrames, uint32_t channels, double sampleRate);
SonanceAnalysisCapture *SonanceRenderAnalysis(SonanceRender *render);
void SonanceRenderReleaseResources(SonanceRender *render);
void SonanceRenderReset(SonanceRender *render);
AUInternalRenderBlock SonanceRenderMakeBlock(SonanceRender *render);

NS_ASSUME_NONNULL_END
