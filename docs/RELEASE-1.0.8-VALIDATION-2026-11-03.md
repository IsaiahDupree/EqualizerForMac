# Sonance EQ 1.0.8 (11): validation and App Review record

On November 3, 2026 at 8:24 PM Eastern, Apple's API and the real App Store
Connect page both showed **1.0.8 (11), Waiting for Review**. Build 11 was
processed as VALID and attached to that exact macOS version. The submission
was sent at `2026-11-04T01:23:04.525Z`. Release policy is AFTER_APPROVAL.

The prior one-item 1.0.7 review was withdrawn only after the replacement build
became VALID. Its listing assets and existing review contact were preserved.
English and French release notes and review notes describe the actual new
coverage. The content-rights answer now reflects the licensed preset data.
Both locale readiness audits passed, including three screenshots per locale,
the approved Pro purchase, price schedule, published App Privacy and export
compliance. Waiting for Review is a submitted update, not a public release.

## Passing software tests

| Check | Result |
| --- | --- |
| Full native regression | 281 methods / 4,297 runs passed; 16 opt-in methods skipped in the regular scheme |
| Headphone catalog, included above | All 21 methods / 50 runs passed |
| Separate local StoreKit gate | All 15 methods / 25 runs passed; no skips |
| Python configuration and data suite | 66 passed, five optional checks skipped; 71 total |
| Catalog data, included above | All nine tests passed |
| Merged-main GitHub workflow | All five jobs passed |
| Actual archived MAS app | Version, build, purchase configuration and bundled resources verified |

The regular scheme skips 15 StoreKit methods and one opt-in system-audio
hardware test. Those 15 StoreKit methods passed in the dedicated scheme using
real local Apple transactions. This checks purchase, restore, refund and
transaction-history behavior; it does not verify RevenueCat's live server
receipt-to-entitlement hop. The Python skips require supplied packages,
compiled native runners or an incremented native build. CI separately builds
and checks real default and incremented MAS candidates.

The actual archived 1.0.8 app also passed the metadata-only purchase gate.
Its first Xcode settings lookup timed out; warming the real settings cache
took 6.07 seconds, after which the unchanged gate passed. No assertion or
production licensing code was relaxed.

## New coverage exercised through shipping code

- AirPods Pro 3 retains the six exact published filters, matching -3.9 dB
  preamp, shipping AppState application and shareable-preset import.
- All 11 OPRA additions load with their exact bands, creator, source and
  license. The bundled data, license text and logo match the tested source.
- The shipping filter implementation produces finite responses and stable
  poles, with nonpositive peak gain after preamp, at 44.1, 48, 96 and 192 kHz.
- Searches cover Beats by Dre aliases, spaced generation names, Plus models,
  literal SQL special characters, category identity and missing generations.
- Real SQLite tests preserve all 8,851 original rows and acoustic values,
  reject duplicate additions, verify source/license hashes and retain the
  previous database when a real rebuild fails.

The archived database contains 8,862 corrections, including 55 Beats
corrections. Its SHA-256 is
`5e57770a181181f892e7153ef942a48ff0ffdd014dc077827aac57ba5a0ee8e3`.
The archived app contains both arm64 and x86_64 code. Optional usage
event delivery is unconfigured in this release; the actual archived public
purchase key is configured.

These checks establish software and data behavior. They do not establish
physical headphone fit, audibility or individual-unit calibration. Exact
models without redistributable correction data remain documented gaps in the
[coverage inventory](HEADPHONE-COVERAGE-2026-11-03.md), including Powerbeats Fit
and Beats 360.

## Source and evidence

The packaged source is `efd04e365fe9ead75cdb3a2520bb03dd70e188a8`, merged as
`bdb8fa21e600454785078ee1781c6bfeaf2ad151` in
[PR #9](https://github.com/IsaiahDupree/EqualizerForMac/pull/9). Their source
trees were verified identical before delivery. This release-record change is
documentation only.

- [Passing merged-main workflow](https://github.com/IsaiahDupree/EqualizerForMac/actions/runs/41751264178)
- [Passing PR workflow](https://github.com/IsaiahDupree/EqualizerForMac/actions/runs/41747956166)
- Native cases: [`Tests/StoreTests.swift`](../Tests/StoreTests.swift), `PresetStoreTests`
- Data tests: [`Tools/tests/test_headphone_presets.py`](../Tools/tests/test_headphone_presets.py)
- StoreKit gate: [`Tests/StoreKitIntegrationTests.swift`](../Tests/StoreKitIntegrationTests.swift)

Full local Xcode results, signed archive, installer, audit logs, resource hashes
and private API/UI observations are retained outside Git with the AppFleet
release artifacts. Contact details and desktop captures are not published.
