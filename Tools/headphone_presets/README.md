# Supplemental headphone presets

These are published preset **data**, imported with attribution. No external app
implementation is copied. `manifest.json` pins the source, checksum, measurement
reference and filter count. `build_autoeq_db.py` appends these entries after the
original AutoEq catalog. The runtime remains an offline, read-only SQLite lookup.

## Apple AirPods Pro 3

- Six peaking filters and a -3.9 dB preamp, reproduced unchanged from
  [openEq's published preset](https://github.com/sean-o-sullivan/open-mac-eq/blob/929aa9145b6734fba0ea39a223d5bb636948d4cc/AirPodsEQSpike/Presets/airpods-pro-3-songbird-jm1-6band.txt).
- Target: JM-1 with -10 dB tilt. This is a target-based starting point for the
  Pro 3, not a personalized hearing correction or a Pro 2 curve.
- The upstream author identifies the result as Songbird's AutoEQ on the L/R
  average. [Songbird's measurement page](https://songbird.rocks/catalog/apple-airpods-pro-3)
  credits earphonesarchive and a B&K 5128 rig. The listening mode is unspecified;
  do not label the preset ANC-only or promise a correction for every mode.
- Reviewed on November 3, 2026. The upstream preset's retrieval date is retained
  in the unmodified source file. Fit, seal, firmware and listening volume can
  affect the response; this addition has no physical Pro 3 audibility proof.
- Distributed under the upstream MIT license, copied into the app bundle as
  `openEq-LICENSE.txt`. The About panel links to the pinned preset and credits
  Songbird and openEq separately from Jaakko Pasanen's AutoEq catalog.

Rebuild using the existing reference corpus (no network/generation at runtime):

```sh
python3 Tools/build_autoeq_db.py --results /absolute/path/to/AutoEq/results
```

The complete bundled catalog is 8,851 entries: 8,850 existing corrections plus
this six-band Pro 3 preset. The native catalog tests search the actual app-bundled
database, verify the published filters, apply them through `AppState`, and check
the response and preamp headroom at supported test sample rates.

## Use with the current release

Download [the importable preset](../../Sources/SonanceEQ/Resources/Apple-AirPods-Pro-3.sonanceeq.json),
open Sonance EQ, choose **Import**, and select that JSON file. Import is included
in Pro. This applies the same six bands and preamp without waiting for a new
bundled-catalog release. The file also carries its source links and MIT notice.
