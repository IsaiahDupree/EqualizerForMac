# French Localization Experiment — 1.0.6

## Decision

Version 1.0.5 already contains the first `fr-FR` App Store localization and is
`WAITING_FOR_REVIEW`. Do not modify that submission. Use it as the French-listing baseline, then ship
the corrected in-app paywall localization and de-duplicated French keyword treatment in 1.0.6.

Apple Product Page Optimization cannot randomize title, subtitle, description, promotional text, or
keywords. This is therefore a territory-level before/after test, not a randomized A/B test. Do not call
it causal until the committed observation window and sample threshold are met.

## Hypothesis

Because Sonance EQ already reaches international users and 1.0.5 introduces French listing copy, we
believe removing duplicate indexed terms, using the full keyword byte budget, and making every native
paywall element render in French will increase first-time downloads per product-page view and preserve
purchase intent in French storefronts.

## Treatment

- Subtitle: `Égaliseur pour chaque app` (25 characters)
- Keywords: 100/100 UTF-8 bytes, with no title/subtitle repetition
- Refined French description and promotional text (staged only; keep 1.0.5 unchanged for baseline)
- Complete French native paywall, including runtime feature rows, price CTA, restore, dismiss, and
  test-store states
- Active locale attached to each local purchase-funnel event for diagnostics

The English treatment also removes duplicate indexed terms and changes the subtitle to
`Tune every app's playback` (25 characters). These subtitles omit Apple product
terms following the October 2 guideline 5.2.5 metadata rejection.

## Metrics and call rule

- Primary: French-storefront first-time downloads / product-page views
- Secondary: impressions, product-page views, paywall impressions, purchase starts, completed purchases
- Guardrails: purchase failure rate, refunds, crash rate, rating average
- Observation window: at least 28 full days before and 28 full days after release
- Sample threshold: 550 French product-page views in each period for a large (50%) relative-lift call
- Low-volume rule: below the threshold, report the result as directional and do not declare a winner

Do not change French screenshots, price, acquisition campaigns, or paywall value proposition during the
measurement window. Record any unavoidable external event in the release notes before reading results.

## Release procedure

```bash
python3 Tools/asc/metadata.py --validate-only
source Tools/asc/env.sh
python3 Tools/asc/metadata.py --version 1.0.6 --dry-run
# Only after 1.0.6 exists in PREPARE_FOR_SUBMISSION and the dry run is reviewed:
python3 Tools/asc/metadata.py --version 1.0.6 --apply
```

The tool refuses writes to a version in review or already on sale. App Store Connect Analytics remains
the source of truth for storefront acquisition; the app's Purchase Analytics panel is local diagnostic
evidence, not cross-user telemetry.
