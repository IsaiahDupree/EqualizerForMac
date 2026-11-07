# Sonance EQ desktop preview

Open `SonanceEQ.exe` on Windows or `SonanceEQ` on Linux from the extracted folder.
Keep the `_internal` directory beside the executable. Python is included.

This preview is a working desktop preset editor. It supports parametric bands,
draggable frequency-response points, preamp and bypass preview, the bundled AutoEq
headphone library, JSON import/export, saved presets and session restoration.
The response is calculated by the original Sonance C++ core.

System-wide audio processing is not connected in this preview. Editing a preset
does not change the audio playing in other applications. Native audio adapters,
hardware qualification and release installation/signing remain separate work.

Headphone corrections retain the AutoEq MIT attribution. Original Sonance code,
Qt/PySide6, Python and the packaging components have separate license terms;
see `THIRD-PARTY-NOTICES.md` and `OPEN-SOURCE-LICENSES`. Qt libraries are dynamically
linked and unmodified. This is an owner development preview, not a Store release.
