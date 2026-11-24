#import <AudioToolbox/AUAudioUnitImplementation.h>
#import "../Shared/SonanceAnalysis.h"

NS_ASSUME_NONNULL_BEGIN

// Each filter slot reserves enough sections for a 96 dB/oct cut.
enum { SonanceRenderBands = 32, SonanceSectionsPerBand = 8,
       SonanceRenderSections = SonanceRenderBands * SonanceSectionsPerBand,
       SonanceRenderCoefficientCount = 5 * SonanceRenderSections,
       SonanceFIRLength = 2048 };

typedef struct SonanceRender SonanceRender;

SonanceRender *_Nullable SonanceRenderCreate(void);
void SonanceRenderDestroy(SonanceRender *render);
void SonanceRenderStage(SonanceRender *render, const double *midCoefficients,
                        const double *sideCoefficients, bool midSideEnabled,
                        const float *midFIR, const float *sideFIR, bool linearPhaseEnabled);
bool SonanceRenderPrepare(SonanceRender *render, AUAudioFrameCount maxFrames, uint32_t channels, double sampleRate);
SonanceAnalysisCapture *SonanceRenderAnalysis(SonanceRender *render);
uint64_t SonanceRenderCompletedBlocks(SonanceRender *render);
uint64_t SonanceRenderDeadlineMisses(SonanceRender *render);
uint64_t SonanceRenderMaximumProcessingNanoseconds(SonanceRender *render);
uint64_t SonanceRenderLastDeadlineNanoseconds(SonanceRender *render);
void SonanceRenderReleaseResources(SonanceRender *render);
void SonanceRenderReset(SonanceRender *render);
AUInternalRenderBlock SonanceRenderMakeBlock(SonanceRender *render);

NS_ASSUME_NONNULL_END
