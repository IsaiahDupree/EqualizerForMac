# Purchase and restore verification — 2026-10-09

The native paywall previously displayed a fixed `$9.99` while purchasing an offering's first package.
The hosted paywall reported restore completion and dismissed before checking whether Pro was active.
This source change binds price and purchase to the approved Pro package, applies callback entitlements
immediately, and keeps an empty restore or unsuccessful unlock on the recovery screen.

## Source behavior

- Only `com.isaiahdupree.SonanceEQ.pro`, a non-consumable with a nonempty StoreKit price, is eligible.
  Current and named offerings are searched for that exact SKU. A missing package disables the native
  purchase button and exposes a localized retry action; no fixed or invented price is shown.
- The native paywall passes the displayed `Package` instance to the purchase call. The locked headphone
  library opens this paywall instead of starting a purchase without its price and recovery controls.
- A purchase/restore callback reports success only when its actual `CustomerInfo` has active Pro and
  the newest access state is still Pro. Empty restores record `restoreNoEntitlement`; purchase results
  without Pro record `purchaseFailed`. Cancellation and existing event/schema names are preserved.
- Older callback timestamps cannot replace newer access. An entitlement revision invalidates an
  overlapping refresh result or error, including timestamp ties. Foreground refresh requests fresh
  CustomerInfo through RevenueCat's `fetchCurrent` policy.
- A hosted paywall uses the exact resolved offering only when it has one authorized package and the
  app language is English. French and the eight added app languages use the native catalog while
  hosted translations remain unverified. No dashboard configuration was changed.
- Four new keys were added to English and all eight packs (`pl`, `vi`, `cs`, `it`, `pt-PT`, `el`, `hu`,
  `zh-Hant`), bringing each complete table to 161 keys. French received those four keys and the existing
  missing purchase-unavailable error. Existing French strings and assertions remain intact.

## Native results

All commands ran serially on the Mac with `-jobs 1 -parallel-testing-enabled NO`, single-file Swift
compilation and `OTHER_SWIFT_FLAGS=-j1`. No simulator was used. The final source after the headphone
library reroute passed the full normal suite and the final App Store configuration build.

| Check | Result | Actual scope |
| --- | --- | --- |
| Normal hosted Swift Testing, `SonanceEQ` | PASS: 247 functions / 4,218 runs; zero failures | All existing assertions, bundled language parity/format/permission checks, French paywall assertions; seven StoreKit methods intentionally skipped here |
| Isolated `SonanceEQ-StoreKit` | PASS: 7 methods / 17 runs; zero failures or skips | Four retained Apple transaction/gating tests; actual Product/StoreProduct price identity in 11 configured storefront/locale pairs; empty restore; purchase, restore, refund and delayed callback outcomes |
| `Release-MAS` build, signing disabled | PASS, exit 0 | App Store source configuration compiles, including real RevenueCat provider and public-permission path; build was not launched or uploaded |

The isolated price cases configured USA/en_US, Poland/pl_PL, Vietnam/vi_VN, Czechia/cs_CZ, Italy/it_IT,
Portugal/pt_PT, Greece/el_GR, Hungary/hu_HU, Taiwan/zh_TW, Hong Kong/zh_HK and France/fr_FR. They check
that the package preserves the actual **local StoreKit** `Product.displayPrice`; they do not assert
the live App Store price in any market. The existing `.storekit` test configuration price is unchanged.

The callback cases observe verified `Transaction.currentEntitlements` after local Apple
purchase/refund operations, then adapt those observed transaction fields to RevenueCat's public value
types and exercise the shipping callback policy. No fake provider or backend response was added.
This proves local transaction-to-policy behavior. RevenueCat's server receipt-to-entitlement mapping
and the hosted dashboard purchase flow were not exercised.

Local result paths (not committed binary artifacts):

- `/tmp/SonanceEQ-Revenue-20261009-final-regression.xcresult`
- `/tmp/SonanceEQ-Revenue-20261009-storekit.xcresult`
- `/tmp/SonanceEQ-Revenue-20261009-final-release-mas.log`

CI now runs the isolated opt-in scheme after normal tests, preserving the separate serial StoreKit
gate. The documented `SKIP_SONANCE_TESTS=1` commit-hook option was used only after these equivalent
normal checks and isolated checks completed, so Git does not reopen the shared native build slot.

## Release acceptance still required

Before a distribution release, verify the configured RevenueCat offering resolves this approved SKU,
the server maps a sandbox purchase to active `pro`, and purchase/restore/cancel/refund/relaunch work
through the real provider. Verify the displayed live StoreKit price and hosted English copy against
that same offering. Review native translations, layouts and VoiceOver with fluent speakers; verify
remote hosted translations before enabling them for other app languages.

The source packs and App Store metadata drafts are separate from live store listings. No price,
offering, dashboard paywall, App Store listing or submission was changed in this pass.
