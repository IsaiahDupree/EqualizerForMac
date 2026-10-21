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
