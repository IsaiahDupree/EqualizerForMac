#include <stdint.h>

typedef struct MDPAtomicFloat MDPAtomicFloat;
MDPAtomicFloat * _Nullable MDPAtomicFloatCreate(float value);
void MDPAtomicFloatDestroy(MDPAtomicFloat * _Nonnull value);
float MDPAtomicFloatLoad(MDPAtomicFloat * _Nonnull value);
void MDPAtomicFloatStore(MDPAtomicFloat * _Nonnull value, float input);
