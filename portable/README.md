# Sonance EQ portable core

This directory starts the Windows/Linux core-EQ port. It contains an original,
dependency-free C++17 IIR processor and Python preset/database tools. It is a
library and command-line tooling, not an installable system equalizer yet.

The [cross-platform delivery plan](../docs/WINDOWS-LINUX.md) records the Windows
audio integration, Linux routing, desktop UI and Store release work still needed.

## DSP

`include/sonance/eq.hpp` provides all eight existing Sonance filter shapes,
Butterworth cuts at 6–96 dB/octave, preamp, bypass, a response evaluator and
stateful mono/stereo processing. Coefficients are double precision; buffers are
interleaved Float32. Preparation clamps frequency below the current Nyquist limit
and rejects invalid values or chains exceeding 32 sections. The Mac currently
truncates excess sections; this core deliberately reports that condition.

The callback path allocates no memory, takes no locks and calls no OS API.
`Configuration::prepare` is a control-thread operation. `configure` and `reset`
must run only while processing is stopped; one thread owns each processor and
its channel layout stays fixed for the stream. Live UI parameter transfer and
click-free wet/dry transitions still need platform integration. Immediate bypass
has no transition ramp. This library does not include FIR, Mid-Side, an audio
driver, an APO, a device router, a limiter or a GUI.

```cpp
#include <sonance/eq.hpp>

sonance::Band band{sonance::FilterType::peaking, 1000, 3, 1.2};
auto settings = sonance::Configuration::prepare(&band, 1, 48000, -6);
sonance::Processor processor;
processor.configure(settings); // stream stopped
// In the owning audio callback: processor.process(buffer, frames, 2);
```

The processor preserves floating-point headroom rather than hard-clipping.
Non-finite input becomes silence. Non-finite/overflowing output silences that
sample and resets that channel's history. Output can exceed [-1,1], so the native
adapter must apply an appropriate output/headroom policy before hardware delivery.

## Presets and headphones

`presets.py` preserves the actual Mac `PresetFile` v1 field names and the legacy
12 dB/octave default. Unknown versions/fields, duplicate JSON fields, invalid
numbers and excess section counts produce explicit errors. Python 3.10+ is needed.

```sh
python3 portable/presets.py search Sennheiser --limit 5
python3 portable/presets.py export 2313 > /tmp/sonance-headphone.json
python3 portable/presets.py validate /tmp/sonance-headphone.json
```

Search/export reads the existing `Sources/SonanceEQ/Resources/autoeq.sqlite` in
read-only mode. `--database PATH` selects an actual separately packaged copy.
An absent database is an error, never an empty success or a seeded replacement.
The original AutoEq attribution and MIT notice in `THIRD-PARTY-NOTICES.md` must
accompany a distributed copy. No upstream project code has been imported.

## Verification

Small, serial compiler/unit checks (no network or package installation):

```sh
python3 portable/tests/verify.py
python3 -m unittest discover -s portable/tests -p 'test_*.py' -v
# Mac only: compare against shipping Swift coefficients and preset serialization.
python3 portable/tests/verify.py --swift-parity
# Address and undefined-behavior sanitizer run; reported separately.
python3 portable/tests/verify.py --sanitize
```

An optional CMake/CTest target is provided for native toolchains:

```sh
cmake -S portable -B build/portable
cmake --build build/portable --parallel 1
ctest --test-dir build/portable --output-on-failure
```

Full native builds and sustained audio qualification belong on Orion through a
registered typed build job. The current Orion worker inventory does not include
a Sonance/C++ desktop build profile; native Windows/Linux compilation, the CMake
route, latency and real hardware behavior have not been verified. Host unit
checks and mathematical parity do not establish those properties.
