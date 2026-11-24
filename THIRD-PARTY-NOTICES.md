# Third-Party Notices

Sonance EQ includes or builds upon the following third-party components. Each is the property of its
respective authors and is used under its own license.

---

## iOS 27 Media Device route experiment

The debug-only `iOS/RouteExperiment` target adapts
[`ios27-media-device-passthrough`](https://github.com/satomasahiro2005/ios27-media-device-passthrough)
by nemut.ai, commit `0ed6091ec6e82d5aa9fb4320bef7a083260f6a0f`, under the
MIT No Attribution license retained in `iOS/RouteExperiment/UPSTREAM-LICENSE`.
It is not integrated with the production app or approved for distribution.

---

## Headphone correction catalog

The bundled headphone catalog (`Resources/autoeq.sqlite`, 8,862 entries in the
November 2026 catalog) includes 8,850 AutoEq corrections, 11 supplemental OPRA
presets and one Songbird / openEq preset. Each source retains its own attribution
and license.

### AutoEq — headphone correction data

The AutoEq corrections were derived from the **AutoEq** project by Jaakko
Pasanen, used under the **MIT License**.

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

### OPRA — supplemental headphone correction data

Eleven Beats corrections use source data from **OPRA**, pinned at commit
`0b88ecd4e2bef7cf69fd5d50f1d06fb586c10865`. The curated filter values are
adapted for Sonance EQ and distributed under **Creative Commons
Attribution-ShareAlike 4.0 International**. The full license is bundled as
`Sources/SonanceEQ/Resources/OPRA-LICENSE.txt`.

Source: https://github.com/opra-project/OPRA
License: https://creativecommons.org/licenses/by-sa/4.0/

### Songbird / openEq — AirPods Pro 3 correction

The six-band AirPods Pro 3 correction by Songbird is adapted from openEq under
the **MIT License**. The full license is bundled as
`Sources/SonanceEQ/Resources/openEq-LICENSE.txt`.

Source: https://github.com/sean-o-sullivan/open-mac-eq/blob/929aa9145b6734fba0ea39a223d5bb636948d4cc/AirPodsEQSpike/Presets/airpods-pro-3-songbird-jm1-6band.txt

---

## RevenueCat — purchases SDK

In-app purchases use the **RevenueCat** `purchases-ios` SDK, licensed under the **MIT License**.
Copyright (c) RevenueCat, Inc. — https://github.com/RevenueCat/purchases-ios

---

## Apple frameworks & references

- **Accelerate / vDSP** (Apple) — biquad and FFT processing, used under the Apple SDK license.
- The EQ coefficient formulas follow the **RBJ Audio EQ Cookbook** by Robert Bristow-Johnson (public
  reference material; the implementation here is original).
