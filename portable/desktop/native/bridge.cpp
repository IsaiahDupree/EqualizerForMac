#include "bridge.h"
#include <sonance/eq.hpp>
#include <algorithm>
#include <cstdio>
#include <exception>

uint32_t sonance_abi_version(void) { return 1; }
size_t sonance_band_v1_size(void) { return sizeof(SonanceBandV1); }

int32_t sonance_response_v1(const SonanceBandV1* bands, size_t band_count,
                          double sample_rate, double preamp_db, int32_t bypassed,
                          const double* frequencies, double* response_db, size_t point_count,
                          char* error, size_t error_capacity) {
    if (error && error_capacity) error[0] = '\0';
    try {
        if (band_count > 32 || (band_count && !bands) || !frequencies || !response_db ||
            point_count == 0 || point_count > 4096 || (bypassed != 0 && bypassed != 1))
            throw std::invalid_argument("Invalid native response request");
        std::array<sonance::Band, 32> native{};
        for (size_t i = 0; i < band_count; ++i) {
            if (bands[i].type < 0 || bands[i].type > 7 || (bands[i].enabled != 0 && bands[i].enabled != 1))
                throw std::invalid_argument("Invalid filter type or enabled value");
            native[i] = {static_cast<sonance::FilterType>(bands[i].type), bands[i].frequency,
                         bands[i].gain_db, bands[i].q, bands[i].enabled == 1, bands[i].slope_db_per_oct};
        }
        const auto config = sonance::Configuration::prepare(native.data(), band_count, sample_rate, preamp_db);
        std::array<double, 4096> output{};
        for (size_t i = 0; i < point_count; ++i) {
            const double magnitude = config.magnitude(frequencies[i]);
            if (!std::isfinite(magnitude)) throw std::invalid_argument("Response exceeds the supported range");
            output[i] = bypassed ? 0 : 20 * std::log10((std::max)(magnitude, 1e-12));
        }
        std::copy_n(output.data(), point_count, response_db);
        return 0;
    } catch (const std::exception& exception) {
        if (error && error_capacity) std::snprintf(error, error_capacity, "%s", exception.what());
        return 1;
    } catch (...) {
        if (error && error_capacity) std::snprintf(error, error_capacity, "%s", "Native response calculation failed");
        return 2;
    }
}
