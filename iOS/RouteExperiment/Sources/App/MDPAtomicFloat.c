#include "MDPAtomicFloat.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio parameter must be lock-free");
_Static_assert(sizeof(float) == sizeof(uint32_t), "Expected 32-bit Float");

struct MDPAtomicFloat { _Atomic(uint32_t) bits; };

MDPAtomicFloat *MDPAtomicFloatCreate(float value) {
    MDPAtomicFloat *result = malloc(sizeof(*result));
    if (!result) return NULL;
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    atomic_init(&result->bits, bits);
    return result;
}

void MDPAtomicFloatDestroy(MDPAtomicFloat *value) { free(value); }

float MDPAtomicFloatLoad(MDPAtomicFloat *value) {
    uint32_t bits = atomic_load_explicit(&value->bits, memory_order_relaxed);
    float result;
    memcpy(&result, &bits, sizeof(result));
    return result;
}

void MDPAtomicFloatStore(MDPAtomicFloat *value, float input) {
    uint32_t bits;
    memcpy(&bits, &input, sizeof(bits));
    atomic_store_explicit(&value->bits, bits, memory_order_relaxed);
}
