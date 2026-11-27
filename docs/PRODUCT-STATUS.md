# Sonance EQ — product status

Updated: 2026-10-21

## Store and customer evidence

- Public Mac App Store version: 1.0.6, build 9 (App Store Connect portfolio snapshot, checked 2026-10-21).
- A read-only public review-feed sweep checked 28 currently public apps across 13 major storefronts on 2026-10-21: 323 feed requests succeeded and 41 returned HTTP 403. Sonance EQ's feed succeeded in all 13 checked storefronts and returned one one-star U.S. review dated 2026-08-11, titled “Failed to work on my MacBook.” The reviewer reports inability to route audio, including with a Scarlett 2i2. This is a single reported configuration, not a reproduced defect or proof that all MacBook or Scarlett configurations fail.
- The storefront sweep does not include every App Store territory or private support feedback.
- No current app-specific production usage dataset was verified for Sonance EQ in this pass. Downloads, retention, and route success rates remain unknown.

## Source and release state

- The source release record identifies 1.0.7/build 10 as the next candidate after the live 1.0.6/build 9. It includes route-start responsiveness and lifecycle work; it is not evidence that 1.0.7 is on sale.
- Existing hardware-probe notes explicitly say they do not establish successful routing on the reported MacBook/Scarlett combination. Do not claim the review issue is fixed without a device reproduction and a verified App Store build.
- No build was uploaded or submitted as part of this status update.

## Ranked follow-up

1. Reproduce route start and audible output on the reported MacBook/Scarlett configuration, with permission state and output-device selection recorded. If unavailable, keep the report unresolved.
2. Verify candidate build 10 with the release binding and actual supported hardware; keep device-specific acceptance separate from unit tests and compile success.
3. Preserve explicit permission guidance and actionable route errors; do not change privacy behavior or request additional data collection to address a routing report.

## Evidence boundaries

The public review, source release notes, hardware probe, and App Store version are separate evidence sources. A source fix or locally built candidate does not establish that the public binary contains it or that audio is audible on the reported hardware.

## Customer-review refresh — 2026-11-27

- The App Store Connect customer-review feed now returns two distinct public reports for Sonance EQ. The U.S. one-star report from 2026-08-11 still says output routing failed on a MacBook with and without a Scarlett 2i2. A Poland two-star review dated 2026-11-13 is titled “Promises a lot, fails to deliver” and says Pro lacks a menu-bar icon/menu, automatic default-preset loading, and a less cumbersome preset workflow; it also requests OS login launch and lists dark mode as optional.
- The review API response does not include an App Store version relationship. At the review date 1.0.8 was the latest saleable version; 1.0.9 was under review and later rejected. Treat 1.0.8 as the likely context, not a verified per-review version attribution.
- Current source already has candidate work in draft PR #10 for native menu-bar access and PR #11 for a free listening preview, routing recovery, and automatic preset recall by output device. These are unreleased draft changes. The current import/export flow still relies on files; the latest review indicates that a named in-app preset library may still be useful. It also asks for launch at login; no automatic-login behavior was added or enabled.
- The owner-only first-party 30-day Sonance feature report checked 2026-11-27 records zero production events/installations for Sonance EQ. This is a tracking-coverage gap, not evidence of no use. It cannot establish conversion or quantify demand for the requested features.
- App Store Connect's latest 1.0.9 version is `REJECTED`; the exact Resolution Center reason is not available in the API or notification email. Do not treat either customer review as Apple's rejection finding. Hardware routing, the current rejection reason, and physical acceptance remain separate open questions.

No source, App Privacy, listing, upload, review reply, or submission change was made by this review refresh.

## Current market comparison — 2026-11-27

- Rogue Amoeba's current SoundSource materials position it as a menu-bar audio-control app. Its official manual documents a built-in 10-band equalizer, saved presets, and menu-bar controls. [Product](https://www.rogueamoeba.com/soundsource/), [effects manual](https://www.rogueamoeba.com/support/manuals/soundsource/?page=built-in-effects), [menu-bar controls](https://rogueamoeba.com/support/manuals/soundsource/?page=menu-bar-controls).
- eqMac's official site lists a parametric equalizer, app-volume mixer, configurable interface, and Audio Unit hosting. [eqMac](https://eqmac.app/).
- These are feature-positioning checks, not comparative CPU, latency, audio-quality, or conversion benchmarks. They reinforce the specific customer request for discoverable menu-bar entry and a straightforward preset workflow; they do not establish which feature will improve retention or willingness to pay.
- PR #10's native menu-bar candidate and PR #11's output-specific preset recall cover only parts of this parity gap. A named in-app preset library and easier preset organization remain open product candidates. Keep login-at-start opt-in if pursued; no automatic launch behavior or privacy/tracking change is authorized by this evidence.
- The current App Store Connect feed still returns only the three portfolio reviews listed in the portfolio report. Sonance EQ's two reviews are not version-linked; feature changes remain candidates pending source review, validation, and release approval.
