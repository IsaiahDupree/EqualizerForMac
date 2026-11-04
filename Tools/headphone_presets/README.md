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

The 1.0.7 catalog contains 8,851 entries: 8,850 existing corrections plus
this six-band Pro 3 preset. The native catalog tests search the actual app-bundled
database, verify the published filters, apply them through `AppState`, and check
the response and preamp headroom at supported test sample rates.

## Beats expansion for 1.0.8

The catalog now contains **8,862 corrections**, including **55 Beats corrections**.
Eleven additional published corrections come from [OPRA](opra/README.md), with
creator attribution and the CC BY-SA 4.0 data license. These are additional
curves for existing Beats models; they do not establish support for a different
generation. All 8,851 original database rows, IDs and acoustic values are retained.

Search now accepts `Beats by Dre`, `Beats by Dr. Dre`, spaced generation names
such as `Solo 3`, and `Studio Buds Plus`. The `+` distinguishes Buds + from Buds.
Display metadata corrects the duplicate `Beats Beats` name, inconsistent Apple
names, and the upstream over-ear classification of Powerbeats 2 Wireless.
Original measurement labels remain in the `presets` table.

`coverage.json` records the current official Beats lineup, the requested newer
devices and named legacy gaps. A real device appearing in that inventory is
**not** a bundled preset. Missing generations never receive another model's EQ.

Before expanding or describing coverage, run:

```sh
python3 Tools/audit_headphone_coverage.py
python3 Tools/audit_headphone_coverage.py --check-upstream --fail-on-new-release --json
```

The optional online check reads Beats' current headphone/earbud product links
and OPRA's latest revision. Unknown products, an updated source revision or a
failed source lookup require review. The tool does not automatically publish
or import unreviewed data and installs no daemon or scheduled task.

See [the dated coverage report](../../docs/HEADPHONE-COVERAGE-2026-11-03.md) for
the newest and legacy models that still need exact, redistributable preset data.

## Use with the current release

Download [the importable preset](../../Sources/SonanceEQ/Resources/Apple-AirPods-Pro-3.sonanceeq.json),
open Sonance EQ, choose **Import**, and select that JSON file. Import is included
in Pro. This applies the same six bands and preamp without waiting for a new
bundled-catalog release. The file also carries its source links and MIT notice.
