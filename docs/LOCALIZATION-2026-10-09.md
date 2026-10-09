# Eight-language localization cohort

Added Polish, Vietnamese, Czech, Italian, European Portuguese, Greek,
Hungarian and Traditional Chinese. Existing French remains available.
The macOS selected application language resolves the bundled `.lproj` resources.
European Portuguese uses `pt-PT`; Traditional Chinese uses `zh-Hant`, shared
by Taiwan and Hong Kong. These are distinct storefront experiments.

Runtime labels, preset names, permission prompts, app-authored errors,
diagnostics, update notices and format arguments now use native localization.
Device names, user/imported preset names, third-party library attribution,
OS-provided errors and technical symbols retain their original identity.
macOS formats numeric values for the current locale. StoreKit supplies prices.
The existing full-suite pre-commit hook now limits Xcode to one build job and
disables parallel test execution, following the workspace compute policy.
No regional price changes or subscription products are introduced.

The authored translation source is `Tools/localization/translations.tsv`.
Regenerate with `python3 Tools/localization/generate.py`. The shipping bundle
test checks every language for key parity, nonempty values, retained format
arguments and permission copy. Native-speaker review and long-label UI review
remain release checks; source coverage does not prove linguistic quality.

This source change has not been submitted to Apple or released. RevenueCat
dashboard-designed paywalls require separate dashboard translation verification.
The native fallback paywall uses the bundled translations.

## Verified on 2026-10-09

Xcode generated and compiled the native project. The actual bundled-language
integration test and existing French test passed. The complete suite then passed
247 tests (4,218 parameterized runs), with four existing opt-in StoreKit tests
skipped. The source audit reports all eight target catalogs complete. Live
StoreKit transactions, hosted paywalls, native-speaker review and rendered
long-label acceptance were not validated. No Apple upload or release occurred.
