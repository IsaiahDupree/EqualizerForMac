# Headphone catalog coverage — November 3, 2026

The 1.0.8 source candidate adds 11 licensed Beats corrections, for 55 Beats
corrections and 8,862 total entries. The 1.0.7 App Store submission is separate;
this work does not withdraw, replace or modify its submitted build.

## Current Beats lineup

The [official Beats product catalog](https://www.beatsbydre.com/us/products)
currently lists eight headphone/earbud models. Six have corrections in this
candidate. Colors, collaborations and cushion accessories are not counted as
new headphone generations.

| Model | Bundled model-specific preset |
| --- | --- |
| Beats 360 | Pending data |
| Beats Studio Pro | Available |
| Beats Solo 4 | Available |
| Powerbeats Fit | Pending data |
| Powerbeats Pro 2 | Available |
| Beats Studio Buds + | Available |
| Beats Solo Buds | Available |
| Beats Flex | Available |

Beats 360 is already a real product, confirmed by its
[manufacturer page](https://www.beatsbydre.com/headphones/beats-360) and
[Apple's store](https://www.apple.com/shop/buy-beats/beats-360).
It must not receive a Studio Pro curve. Powerbeats Fit must not receive a
Fit Pro curve merely because their names or features are similar.

## Requested newer models still requiring data

| Model | Evidence and remaining prerequisite |
| --- | --- |
| AirPods Max 2 | [Headphones.com measured the exact generation](https://headphones.com/blogs/features/apple-airpods-max-2-frequency-response-measurements-b-k-5128-and-mire). No redistribution-reviewed parametric preset was found. |
| AirPods 5 — USB-C Charging Case | Exact model measurements/preset and redistribution rights needed. |
| AirPods 5 — Wireless Charging Case | [RTINGS measured this variant](https://www.rtings.com/headphones/reviews/apple/airpods-5); a redistributable preset is still needed. Do not assume case variants have identical measured response. |
| Powerbeats Fit | [SoundGuys measured it](https://www.soundguys.com/powerbeats-fit-review-145954/); a commercially redistributable preset is needed. |
| Beats 360 | [SoundGuys measured it](https://www.soundguys.com/product/beats-360/); data must retain listening mode/cushion conditions and permit commercial redistribution. |
| Sony WF-1000XM6 | [Manufacturer identity verified](https://www.sony.com/electronics/support/wireless-headphones-bluetooth-headphones/wf-1000xm6/specifications); a redistribution-reviewed preset is needed. This is distinct from WH-1000XM6. |
| Samsung Galaxy Buds4 Pro | [Manufacturer identity verified](https://www.samsung.com/us/audio-sound/galaxy-buds4-pro/); a redistribution-reviewed preset is needed. |

The reviewed AutoEq snapshot is `7ae0f56d53074872b028649617a22bbb4232feb7`
(July 20, 2025); the current OPRA snapshot is
`0b88ecd4e2bef7cf69fd5d50f1d06fb586c10865` (July 1, 2026).
Their current catalogs and Songbird's catalog do not provide the missing
Apple/Beats generations above. Public GitHub searches did not reveal a
redistribution-reviewed replacement. Published review graphs establish that
measurements exist; they are not themselves a preset redistribution license.
[SoundGuys' actual terms](https://www.soundguys.com/terms-of-use/) explicitly
require permission/licensing for commercial reuse of measurements and
derivatives. No such data has been copied into this release.

## Older Beats coverage and gaps

Available older families include Fit Pro, Studio Buds, Powerbeats Pro,
Powerbeats 4, Powerbeats3 Wireless, Powerbeats 2 Wireless, Solo, Solo HD,
Solo2 (2014), Solo3 (source/year/wired variants), Solo Pro, Studio,
Studio 2 (2014/Bluetooth), Studio3 Wireless, Studio Wireless, Pro, Mixr,
EP, Tour, urBeats, urBeats3 and BeatsX.

This does not cover every historical hardware variant. Apple's
[legacy product records](https://support.apple.com/en-us/102772) identify
additional exact variants without reviewed presets: Executive, Solo2
Wireless, first-generation Powerbeats, Tour 2.5,
second-generation urBeats, Lightning urBeats3, Wireless (1.5), and
Monster-branded Diddybeats, Heartbeats generations 1/2 and iBeats. A generic
Tour or urBeats measurement is not assigned to an unspecified generation.

## Maintaining the catalog

`Tools/headphone_presets/coverage.json` is the dated, evidence-linked inventory.
`Tools/audit_headphone_coverage.py` compares it with the actual SQLite data.
Its optional upstream check reports unfamiliar official Beats product links
and OPRA revision changes; failed lookups return unknown/error, not zero gaps.
It runs only when invoked and changes no product or provider state.

For a missing model, obtain an exact published, redistributable correction or
licensed raw measurements with the matching rig/target and conditions. Pin the
source and license, validate the full filter chain and preamp through the
shipping DSP, and only then add it to the searchable preset database. A
product-name inventory or successful build is not a hardware validation claim.
