# Sonance EQ desktop editor

The Windows/Linux editor lives in `portable/desktop/`. It uses Qt for Python
(PySide6 Essentials 6.10.2) and the original C++ core through a versioned C ABI.
The graph evaluates the native filter cascade; it does not use separate Python
filter equations. The processor remains independent of Qt and Python.

This milestone edits and saves presets. Playback is not connected. Its bypass
button changes the response preview, and its sample-rate selector changes the
response calculation. Neither control configures a system audio endpoint yet.

## Working flows

- Drag a numbered graph handle or select a band and enter its frequency, gain,
  Q, filter shape and cut slope. Enable/disable, add and remove bands.
- Adjust preamp or compare the response with bypass enabled.
- Search the actual bundled AutoEq library and load a headphone correction.
- Import/export the existing Sonance EQ version-1 JSON format, or save a named
  copy in the local preset library.
- Restore the last preset, preview rate and bypass state after restarting.

The editor validates changes with both the existing preset validator and native
core before replacing the document. Invalid imports and chains exceeding 32
processing sections preserve the existing edits. Session and preset writes use
a temporary file in the destination directory followed by atomic replacement.
Unreadable sessions are preserved under a new filename before restoring Flat.

Standard Qt application configuration locations store `session.json` and the
`presets/` directory. The editor does not require an account or network access.
The read-only headphone database retains its existing AutoEq attribution.

## Developer build on Orion

Use the authenticated, serial profiles described in
[`portable/orion/README.md`](../portable/orion/README.md). Dependency setup and
packaging run on Orion; the Mac edits and submits the source snapshot. No GitHub
Actions runner, hosted build or automatic deployment is used.

For an interactive development launch **on the target Orion OS**, after installing
`portable/desktop/requirements.txt` in a dedicated Python environment:

```sh
cmake -S portable -B build/portable -DCMAKE_BUILD_TYPE=Release
cmake --build build/portable --parallel 1
ctest --test-dir build/portable --output-on-failure -j 1
python portable/desktop/app.py
```

The registered Ninja profiles produce the bridge directly in `build/portable`.
For a Visual Studio multi-configuration build, set `SONANCE_EQ_CORE_LIBRARY` to
the actual generated DLL. `SONANCE_EQ_DATABASE` can select an actual separate
read-only database. Frozen preview bundles resolve both resources inside the
bundle and do not require these overrides or a separately installed Python.

Qt widget integration tests use the real native library, database and temporary
files. They exercise mouse/key input, band editing, graph dragging, preamp,
bypass, headphone loading, import/export, named copies and session restoration.
The frozen-app smoke run removes development resource overrides before launch.
Windows additionally launches the packaged app through its normal window backend.
The nine integration tests include actual font glyphs and the compact layout.
Linux rendering is verified with the offscreen backend in Ubuntu WSL2. These
checks do not establish accessibility, physical display scaling or system audio
behavior on every supported desktop. Results and screenshots are in the
[Orion UI report](reports/ORION-DESKTOP-UI-2026-11-07.md).

## Distribution boundary

Preview ZIPs are unsigned developer builds, not Store packages or installers.
Keep their complete directory together. Exact installed dependency notices and
versions accompany each bundle. Qt remains dynamically linked and unmodified;
review corresponding-source and replacement/relinking obligations before any
external release. No commercial Qt license or paid SDK was selected.

System audio integration, smooth live changes, output/device lifecycle handling,
physical playback qualification, install/upgrade/uninstall, signing, licensing
and Microsoft Store certification remain release work. The
[Windows/Linux plan](WINDOWS-LINUX.md) records those platform requirements.
