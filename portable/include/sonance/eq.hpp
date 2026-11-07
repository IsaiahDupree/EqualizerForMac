// Copyright (c) 2026 Isaiah Dupree. See the repository LICENSE.
#pragma once

#include <array>
#include <cmath>
#include <complex>
#include <cstddef>
#include <initializer_list>
#include <limits>
#include <stdexcept>

namespace sonance {

enum class FilterType {
    peaking, lowShelf, highShelf, lowPass, highPass, notch, bandPass, allPass
};

struct Band {
    FilterType type = FilterType::peaking;
    double frequency = 1000;
    double gain_db = 0;
    double q = 0.7071067811865476;
    bool enabled = true;
    double slope_db_per_oct = 12;
};

struct Coefficients {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
};

inline constexpr std::size_t max_sections = 32;
inline constexpr std::size_t max_channels = 2;
inline constexpr double pi = 3.14159265358979323846;

namespace detail {
inline void validate_rate(double rate) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 384000)
        throw std::invalid_argument("sample rate must be between 8000 and 384000 Hz");
}

inline void validate_band(const Band& band) {
    if (!std::isfinite(band.frequency) || band.frequency < 1 ||
        !std::isfinite(band.gain_db) || std::abs(band.gain_db) > 60 ||
        !std::isfinite(band.q) || band.q < 0.0001 || band.q > 100 ||
        !std::isfinite(band.slope_db_per_oct))
        throw std::invalid_argument("invalid EQ band");
    switch (band.type) {
    case FilterType::peaking: case FilterType::lowShelf: case FilterType::highShelf:
    case FilterType::notch: case FilterType::bandPass: case FilterType::allPass:
        return;
    case FilterType::lowPass: case FilterType::highPass:
        for (double slope : {6., 12., 18., 24., 36., 48., 72., 96.})
            if (band.slope_db_per_oct == slope) return;
        throw std::invalid_argument("unsupported cut slope");
    }
    throw std::invalid_argument("unknown filter type");
}

inline Coefficients rbj(const Band& band, double rate, double q) {
    const double f = std::fmin(band.frequency, rate * 0.5 - 1);
    const double a = std::pow(10., band.gain_db / 40.);
    const double w = 2 * pi * f / rate;
    const double c = std::cos(w), alpha = std::sin(w) / (2 * q);
    double b0 = 1, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;
    switch (band.type) {
    case FilterType::peaking:
        b0 = 1 + alpha * a; b1 = -2 * c; b2 = 1 - alpha * a;
        a0 = 1 + alpha / a; a1 = -2 * c; a2 = 1 - alpha / a;
        break;
    case FilterType::lowShelf: {
        const double s = 2 * std::sqrt(a) * alpha;
        b0 = a * ((a + 1) - (a - 1) * c + s);
        b1 = 2 * a * ((a - 1) - (a + 1) * c);
        b2 = a * ((a + 1) - (a - 1) * c - s);
        a0 = (a + 1) + (a - 1) * c + s;
        a1 = -2 * ((a - 1) + (a + 1) * c);
        a2 = (a + 1) + (a - 1) * c - s;
        break;
    }
    case FilterType::highShelf: {
        const double s = 2 * std::sqrt(a) * alpha;
        b0 = a * ((a + 1) + (a - 1) * c + s);
        b1 = -2 * a * ((a - 1) + (a + 1) * c);
        b2 = a * ((a + 1) + (a - 1) * c - s);
        a0 = (a + 1) - (a - 1) * c + s;
        a1 = 2 * ((a - 1) - (a + 1) * c);
        a2 = (a + 1) - (a - 1) * c - s;
        break;
    }
    case FilterType::lowPass:
        b0 = (1 - c) / 2; b1 = 1 - c; b2 = b0;
        a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha;
        break;
    case FilterType::highPass:
        b0 = (1 + c) / 2; b1 = -(1 + c); b2 = b0;
        a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha;
        break;
    case FilterType::notch:
        b0 = 1; b1 = -2 * c; b2 = 1;
        a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha;
        break;
    case FilterType::bandPass:
        b0 = alpha; b1 = 0; b2 = -alpha;
        a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha;
        break;
    case FilterType::allPass:
        b0 = 1 - alpha; b1 = -2 * c; b2 = 1 + alpha;
        a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha;
        break;
    }
    return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}
} // namespace detail

// Immutable after preparation. No OS, device, framework or purchase dependency.
class Configuration {
public:
    Configuration() = default;
    double sample_rate() const noexcept { return rate_; }
    double preamp() const noexcept { return preamp_; }
    std::size_t section_count() const noexcept { return count_; }
    const Coefficients& section(std::size_t index) const { return sections_.at(index); }

    // Control-thread operation. Reject capacity overflow rather than dropping bands.
    static Configuration prepare(const Band* bands, std::size_t count,
                                 double rate, double preamp_db = 0) {
        detail::validate_rate(rate);
        if (count > 32 || (count && bands == nullptr))
            throw std::invalid_argument("expected at most 32 bands");
        if (!std::isfinite(preamp_db) || std::abs(preamp_db) > 60)
            throw std::invalid_argument("preamp must be between -60 and 60 dB");
        Configuration result;
        result.rate_ = rate;
        result.preamp_ = std::pow(10., preamp_db / 20.);
        const auto append = [&](Coefficients c) {
            if (result.count_ == max_sections)
                throw std::invalid_argument("EQ exceeds the 32-section processing capacity");
            result.sections_[result.count_++] = c;
        };
        for (std::size_t n = 0; n < count; ++n) {
            const Band& band = bands[n];
            detail::validate_band(band);
            if (!band.enabled) continue;
            if (band.type != FilterType::lowPass && band.type != FilterType::highPass) {
                append(detail::rbj(band, rate, band.q));
                continue;
            }
            const int order = static_cast<int>(band.slope_db_per_oct / 6);
            for (int i = 1; i <= order / 2; ++i) {
                const double angle = order % 2 ? i * pi / order : (2 * i - 1) * pi / (2 * order);
                append(detail::rbj(band, rate, 1 / (2 * std::cos(angle))));
            }
            if (order % 2) {
                const double f = std::fmin(band.frequency, rate * 0.5 - 1);
                const double k = std::tan(pi * f / rate);
                const double a1 = (k - 1) / (k + 1);
                if (band.type == FilterType::highPass) {
                    const double b = 1 / (1 + k);
                    append({b, -b, 0, a1, 0});
                } else {
                    const double b = k / (1 + k);
                    append({b, b, 0, a1, 0});
                }
            }
        }
        return result;
    }

    // Offline editor/verification utility; not an audio callback operation.
    double magnitude(double frequency) const {
        if (!std::isfinite(frequency) || frequency < 0 || frequency > rate_ / 2)
            throw std::invalid_argument("response frequency outside Nyquist range");
        const std::complex<double> z = std::polar(1., -2 * pi * frequency / rate_);
        auto h = std::complex<double>(preamp_, 0);
        for (std::size_t i = 0; i < count_; ++i) {
            const auto& c = sections_[i];
            h *= (c.b0 + c.b1 * z + c.b2 * z * z) / (1. + c.a1 * z + c.a2 * z * z);
        }
        return std::abs(h);
    }

private:
    std::array<Coefficients, max_sections> sections_{};
    std::size_t count_ = 0;
    double rate_ = 48000, preamp_ = 1;
};

// A processor is owned by exactly one audio thread. Configure/reset only with
// processing stopped. Live coefficient handoff and click-free transitions belong
// in the platform adapter and are not provided by this fixed-configuration core.
class Processor {
public:
    void configure(const Configuration& config) noexcept {
        config_ = config;
        reset();
    }
    void reset() noexcept { state_ = {}; }

    // In-place mono/stereo float processing. No allocation, locks or OS calls.
    // Invalid buffer dimensions are rejected without touching memory. The caller
    // must own frames*channels valid samples; bypass still advances filter state.
    bool process(float* samples, std::size_t frames, std::size_t channels,
                 bool bypass = false) noexcept {
        if (channels == 0 || channels > max_channels ||
            frames > (std::numeric_limits<std::size_t>::max)() / channels ||
            (frames && samples == nullptr)) return false;
        for (std::size_t f = 0; f < frames; ++f) {
            for (std::size_t ch = 0; ch < channels; ++ch) {
                const std::size_t index = f * channels + ch;
                const double dry = std::isfinite(samples[index]) ? samples[index] : 0;
                double value = dry * config_.preamp();
                for (std::size_t s = 0; s < config_.section_count(); ++s) {
                    const auto& c = config_.section(s);
                    auto& delay = state_[ch][s];
                    const double output = c.b0 * value + delay.z1;
                    delay.z1 = c.b1 * value - c.a1 * output + delay.z2;
                    delay.z2 = c.b2 * value - c.a2 * output;
                    if (std::abs(delay.z1) < 1e-24) delay.z1 = 0;
                    if (std::abs(delay.z2) < 1e-24) delay.z2 = 0;
                    value = output;
                }
                // Clear contaminated channel history and silence non-finite output.
                if (!std::isfinite(value) || std::abs(value) > (std::numeric_limits<float>::max)()) {
                    state_[ch] = {};
                    value = 0;
                }
                samples[index] = static_cast<float>(bypass ? dry : value);
            }
        }
        return true;
    }

private:
    struct Delay { double z1 = 0, z2 = 0; };
    Configuration config_;
    std::array<std::array<Delay, max_sections>, max_channels> state_{};
};

} // namespace sonance
