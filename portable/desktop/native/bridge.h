#pragma once
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
# if defined(SONANCE_BUILDING_BRIDGE)
#  define SONANCE_API __declspec(dllexport)
# else
#  define SONANCE_API __declspec(dllimport)
# endif
#else
# define SONANCE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SonanceBandV1 {
    int32_t type;
    double frequency;
    double gain_db;
    double q;
    int32_t enabled;
    double slope_db_per_oct;
} SonanceBandV1;

SONANCE_API uint32_t sonance_abi_version(void);
SONANCE_API size_t sonance_band_v1_size(void);
/* Control-thread response calculation. Writes the output only after validation. */
SONANCE_API int32_t sonance_response_v1(
    const SonanceBandV1* bands, size_t band_count, double sample_rate,
    double preamp_db, int32_t bypassed, const double* frequencies,
    double* response_db, size_t point_count, char* error, size_t error_capacity);

#ifdef __cplusplus
}
#endif
