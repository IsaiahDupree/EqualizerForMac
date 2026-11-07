#include <sonance/eq.hpp>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {
int checks = 0;
void require(bool condition, const std::string& message) {
    ++checks;
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}
void near(double actual, double expected, double tolerance, const std::string& message) {
    require(std::isfinite(actual) && std::abs(actual - expected) <= tolerance, message);
}
template<class Function> void rejects(Function function, const std::string& message) {
    bool rejected = false;
    try { function(); } catch (const std::invalid_argument&) { rejected = true; }
    require(rejected, message);
}
sonance::Configuration prepare(sonance::Band band, double rate = 48000, double gain = 0) {
    return sonance::Configuration::prepare(&band, 1, rate, gain);
}
void response_tests() {
    using namespace sonance;
    for (double rate : {8000., 44100., 48000., 96000., 192000., 384000.}) {
        Band peak{FilterType::peaking, 1000, 6, 1};
        near(20 * std::log10(prepare(peak, rate).magnitude(1000)), 6, 1e-8, "peaking center gain");
        peak.gain_db = -12;
        near(20 * std::log10(prepare(peak, rate).magnitude(1000)), -12, 1e-8, "peaking center cut");
        for (double slope : {6., 12., 18., 24., 36., 48., 72., 96.}) {
            for (auto type : {FilterType::lowPass, FilterType::highPass}) {
                const auto config = prepare({type, 1000, 0, 0.8, true, slope}, rate);
                require(config.section_count() == static_cast<std::size_t>(std::ceil(slope / 12)),
                        "Butterworth section count");
                near(20 * std::log10(config.magnitude(1000)), -3.01029995664, 1e-7,
                     "Butterworth corner gain for each supported order");
            }
        }
        const auto allpass = prepare({FilterType::allPass, 1000, 0, 2}, rate);
        for (double f : {0., 20., 500., 1000., rate * 0.49})
            near(allpass.magnitude(f), 1, 1e-8, "allpass unity magnitude");
        near(prepare({FilterType::bandPass, 1000, 0, 2}, rate).magnitude(1000), 1, 1e-8,
             "bandpass unity center");
        near(prepare({FilterType::notch, 1000, 0, 2}, rate).magnitude(1000), 0, 1e-8,
             "notch center rejection");
        near(20 * std::log10(prepare({FilterType::lowShelf, 1000, 9, 0.7}, rate).magnitude(0)),
             9, 1e-8, "low shelf DC gain");
        near(20 * std::log10(prepare({FilterType::highShelf, 1000, -9, 0.7}, rate).magnitude(rate / 2)),
             -9, 1e-8, "high shelf Nyquist gain");
    }
}
void stream_tests() {
    using namespace sonance;
    const auto flat = Configuration::prepare(nullptr, 0, 48000);
    Processor processor;
    processor.configure(flat);
    std::array<float, 8> samples{{-1, 0.5f, 0, -0.1f, 0.7f, 1, -0.5f, 0.1f}};
    const auto original = samples;
    require(processor.process(samples.data(), 4, 2), "stereo buffer accepted");
    require(samples == original, "flat EQ is exact unity");
    processor.configure(Configuration::prepare(nullptr, 0, 48000, -6));
    require(processor.process(samples.data(), 4, 2), "preamp buffer accepted");
    near(samples[0], -std::pow(10., -6. / 20), 1e-7, "preamp scales real samples");

    const auto config = prepare({FilterType::peaking, 1000, 9, 1.2});
    std::vector<float> signal(32768);
    for (std::size_t i = 0; i < signal.size(); ++i)
        signal[i] = static_cast<float>(0.1 * std::sin(2 * pi * 1000 * i / 48000));
    auto wet = signal;
    processor.configure(config);
    require(processor.process(wet.data(), wet.size(), 1), "mono sine processed");
    double dry_power = 0, wet_power = 0;
    for (std::size_t i = 8192; i < wet.size(); ++i) {
        dry_power += signal[i] * signal[i];
        wet_power += wet[i] * wet[i];
    }
    near(10 * std::log10(wet_power / dry_power), 9, 0.003, "measured sine gain matches requested EQ");

    auto chunks = signal;
    Processor fragmented;
    fragmented.configure(config);
    for (std::size_t i = 0; i < chunks.size();) {
        const auto count = std::min<std::size_t>(37, chunks.size() - i);
        require(fragmented.process(chunks.data() + i, count, 1), "partial block processed");
        i += count;
    }
    require(chunks == wet, "sample history is independent of callback block sizes");

    std::vector<float> stereo(4096 * 2);
    stereo[0] = 0.2f;
    processor.configure(config);
    require(processor.process(stereo.data(), 4096, 2), "stereo impulse processed");
    for (std::size_t i = 0; i < 4096; ++i)
        require(stereo[i * 2 + 1] == 0, "no crosstalk into silent right channel");
    double real = 0, imaginary = 0;
    for (std::size_t i = 0; i < 4096; ++i) {
        real += stereo[i * 2] * std::cos(2 * pi * 1000 * i / 48000);
        imaginary -= stereo[i * 2] * std::sin(2 * pi * 1000 * i / 48000);
    }
    near(std::hypot(real, imaginary) / 0.2, config.magnitude(1000), 1e-6,
         "processed impulse agrees with analytic transfer function");

    auto bypassed = signal;
    processor.configure(config);
    require(processor.process(bypassed.data(), bypassed.size(), 1, true), "bypass buffer processed");
    require(bypassed == signal, "bypass preserves dry samples");
    std::array<float, 128> tail{}, reference_tail{};
    require(processor.process(tail.data(), tail.size(), 1), "wet resumes after bypass");
    require(fragmented.process(reference_tail.data(), reference_tail.size(), 1), "reference wet tail");
    require(tail == reference_tail, "bypass keeps filter history current");
    processor.reset();
    tail = {};
    require(processor.process(tail.data(), tail.size(), 1), "reset buffer processed");
    require(std::all_of(tail.begin(), tail.end(), [](float x) { return x == 0; }), "reset clears history");
}
void validation_tests() {
    using namespace sonance;
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    rejects([&] { Configuration::prepare(nullptr, 1, 48000); }, "missing band memory rejected");
    rejects([&] { Configuration::prepare(nullptr, 0, nan); }, "NaN sample rate rejected");
    rejects([&] { Configuration::prepare(nullptr, 0, 7999); }, "unsupported sample rate rejected");
    rejects([&] { Configuration::prepare(nullptr, 0, 48000, inf); }, "infinite preamp rejected");
    rejects([&] { prepare({FilterType::peaking, nan, 0, 1}); }, "NaN frequency rejected");
    rejects([&] { prepare({FilterType::peaking, 1000, 61, 1}); }, "unbounded gain rejected");
    rejects([&] { prepare({FilterType::peaking, 1000, 0, 0}); }, "zero Q rejected");
    rejects([&] { prepare({FilterType::lowPass, 1000, 0, 1, true, 25}); }, "unsupported slope rejected");
    rejects([&] { prepare({static_cast<FilterType>(999), 1000, 0, 1}); }, "unknown filter rejected");
    const std::array<Band, 5> oversized{{
        {FilterType::lowPass, 1000, 0, 1, true, 96},
        {FilterType::lowPass, 1000, 0, 1, true, 96},
        {FilterType::lowPass, 1000, 0, 1, true, 96},
        {FilterType::lowPass, 1000, 0, 1, true, 96},
        {FilterType::lowPass, 1000, 0, 1, true, 96}}};
    require(Configuration::prepare(oversized.data(), 4, 48000).section_count() == 32,
            "exact section capacity accepted");
    rejects([&] { Configuration::prepare(oversized.data(), 5, 48000); }, "excess sections rejected");
    require(prepare({FilterType::peaking, 1000, 6, 1, false}).section_count() == 0,
            "disabled bands excluded");
    require(std::isfinite(prepare({FilterType::peaking, 1e100, 6, 1}).magnitude(1000)),
            "frequency clamped below Nyquist");
    rejects([&] { prepare({}).magnitude(-1); }, "negative response frequency rejected");

    Processor processor;
    std::array<float, 4> guarded{{0.25f, -0.5f, 0.75f, -1}};
    const auto original = guarded;
    require(!processor.process(guarded.data(), 1, 3), "unsupported channel count rejected");
    require(!processor.process(guarded.data(), 1, 0), "zero channels rejected");
    require(!processor.process(nullptr, 1, 1), "null buffer rejected");
    require(!processor.process(guarded.data(), std::numeric_limits<std::size_t>::max(), 2),
            "frame multiplication overflow rejected");
    require(guarded == original, "invalid dimensions do not modify samples");
    require(processor.process(nullptr, 0, 2), "empty buffer accepted");
    std::array<float, 4> contaminated{{static_cast<float>(nan), static_cast<float>(inf), 0.2f, -0.1f}};
    processor.configure(prepare({FilterType::peaking, 1000, 6, 1}));
    require(processor.process(contaminated.data(), 4, 1), "non-finite input handled");
    require(std::all_of(contaminated.begin(), contaminated.end(), [](float x) { return std::isfinite(x); }),
            "non-finite input cannot poison following samples");
}
} // namespace

int main() {
    response_tests();
    stream_tests();
    validation_tests();
    std::cout << "PASS: " << checks << " DSP assertions\n";
}
