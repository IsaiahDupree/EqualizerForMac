# Third-Party Notices

Sonance EQ includes or builds upon the following third-party components. Each is the property of its
respective authors and is used under its own license.

---

## AutoEq — headphone correction data

The bundled headphone presets (`Resources/autoeq.sqlite`, ~8,850 corrections) are derived from the
**AutoEq** project by Jaakko Pasanen, used under the **MIT License**.

> MIT License
>
> Copyright (c) 2018-2022 Jaakko Pasanen
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
> associated documentation files (the "Software"), to deal in the Software without restriction,
> including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
> and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
> subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial
> portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
> LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
> NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
> WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
> SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Source: https://github.com/jaakkopasanen/AutoEq

---

## Windows/Linux desktop preview

The desktop editor uses unmodified, dynamically linked **Qt / PySide6 / shiboken6
6.10.2** under the LGPLv3 option. These components remain under their own
licenses. Their original license texts, upstream Qt third-party notices and
source references are retained in `portable/desktop/licenses/` and copied into
`OPEN-SOURCE-LICENSES/` in preview bundles. The wheels can omit open-source
license files, so their metadata alone is not treated as a complete notice set.

- Qt source: https://github.com/qt/qtbase/tree/v6.10.2 and
  https://github.com/qt/qtsvg/tree/v6.10.2
- Qt for Python source: https://github.com/pyside/pyside-setup/tree/v6.10.2
- Licensing: https://doc.qt.io/qtforpython-6.10/licenses.html

The editor bundles the unmodified **Inter 4.1** font by Rasmus Andersson and the
Inter Project Authors under the **SIL Open Font License 1.1**. Its exact font
and license are in `portable/desktop/assets/`.
Source: https://github.com/rsms/inter/tree/v4.1

Frozen previews include **Python** under the PSF license. **PyInstaller 6.22.3**
is the packaging tool; its GPL license includes an exception for distributing
applications built with it. Exact runtime/build-tool versions and notices are
recorded in each bundle's `OPEN-SOURCE-LICENSES/packages.json`.
Source: https://pyinstaller.org/en/stable/license.html

These third-party components are excluded from Sonance's original-code license.
The previews are internal developer builds; corresponding-source delivery and
all third-party distribution obligations must be verified before external
distribution or Store submission.

---

## RevenueCat — purchases SDK

In-app purchases use the **RevenueCat** `purchases-ios` SDK, licensed under the **MIT License**.
Copyright (c) RevenueCat, Inc. — https://github.com/RevenueCat/purchases-ios

---

## Apple frameworks & references

- **Accelerate / vDSP** (Apple) — biquad and FFT processing, used under the Apple SDK license.
- The EQ coefficient formulas follow the **RBJ Audio EQ Cookbook** by Robert Bristow-Johnson (public
  reference material; the implementation here is original).
