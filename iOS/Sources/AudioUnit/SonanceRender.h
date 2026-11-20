#import <AudioToolbox/AUAudioUnitImplementation.h>

NS_ASSUME_NONNULL_BEGIN

// A fixed bank of ten Sonance peaking filters, with the preamp folded into section zero.
enum { SonanceRenderSections = 10, SonanceRenderCoefficientCount = 5 * SonanceRenderSections };

typedef struct SonanceRender SonanceRender;

SonanceRender *_Nullable SonanceRenderCreate(void);
void SonanceRenderDestroy(SonanceRender *render);
void SonanceRenderStage(SonanceRender *render, const double *coefficients);
bool SonanceRenderPrepare(SonanceRender *render, AUAudioFrameCount maxFrames, uint32_t channels);
void SonanceRenderReleaseResources(SonanceRender *render);
void SonanceRenderReset(SonanceRender *render);
AUInternalRenderBlock SonanceRenderMakeBlock(SonanceRender *render);

NS_ASSUME_NONNULL_END
