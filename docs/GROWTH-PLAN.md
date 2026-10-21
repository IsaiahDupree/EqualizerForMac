# Growth Plan — Deepen Sonance EQ

Data-driven, because we now have real numbers. Written 2026-07-03.

## Customer review update — 2026-10-21

App Store Connect's customer-review API now returns one USA review (1 star, Aug 11, 2026); the reviewer reports that routing failed on a MacBook both with and without a Scarlett 2i2. No developer response is recorded. The `0` ratings/reviews figure below is the original June 20–July 2 snapshot, not a current count. Public storefront lookup currently reports zero rating counts, which is a separate feed.

Current Sonance EQ source includes `NSAudioCaptureUsageDescription`. Apple's Core Audio tap guidance says macOS prompts for system-audio recording access the first time an aggregate device containing a tap starts ([Core Audio tap capture](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)). PR #4 added route-start and buffer-safety changes, but neither those source changes nor the review identifies whether the reported failure came from permission, the built-in output, the Scarlett route, or another setup detail. Treat this as unresolved until a clean-account first-run permission check and audible route acceptance are recorded on a MacBook with the built-in output and Scarlett tested separately. No fix or release is claimed from the review text alone.

## The funnel (Jun 20 – Jul 2, from Sales Reports API)

| Stage | Number | Verdict |
|---|---|---|
| First-time downloads | **16** (~1.2/day) | 🔴 **binding constraint** |
| Updates | 8 | fine |
| Pro purchases | 1 | |
| **Free → Pro conversion** | **6.25%** | 🟢 healthy (freemium avg 1–5%) — *don't over-tune yet* |
| Ratings / reviews | **0** | 🔴 hurts ranking + trust |
| Countries reached | 10 (US, GB, DE, CA, IN, NZ, DK, CO, RU, UA) | 🟢 organic international pull |

**Diagnosis:** the paywall already converts above average. Money is capped by **traffic (16 downloads) and
social proof (0 reviews)** — not by the paywall. So: **fill the funnel and build proof first; optimize
conversion later.** At a steady 6.25%, every 100 extra downloads ≈ 6 sales ≈ ~$42 proceeds.

---

## Priorities (highest leverage first)

### P0 — In-app review prompt  ← starting here
0 reviews is a ranking + trust anchor. Add SwiftUI `requestReview` after a *positive* moment (e.g. Nth
launch AND user has applied a preset / adjusted the EQ), never on first launch, never on a paywall bounce.
Apple rate-limits it (≤3 prompts/year) so it's safe. **Biggest bang, smallest, safest diff.**

### P1 — App Store listing polish (ASO conversion)
`Tools/asc/metadata.py` already sets subtitle + keywords. Levers that move installs-per-impression:
- **Screenshots** are the #1 conversion driver — show the EQ curve, AutoEq browser, per-app picker in action.
- Tighten the **subtitle** ("System-wide audio equalizer") toward a benefit ("EQ every app on your Mac").
- Broaden **keywords** toward intent terms (boost bass, volume, spatial, per-app, loudness).

### P2 — Traffic (top of funnel)
16 downloads is organic-only. Feed Sonance into the existing content/social ecosystem (LinkedIn/Twitter/
Reddit/YouTube per the global toolchain). One good demo video of "EQ'ing the whole Mac, no driver" is the
asset. r/macapps, r/apple, Product Hunt, MacUpdate.

### P3 — More Pro hooks (conversion, later)
Only touch once traffic is up and n is bigger. Ideas: a "Pro preset of the week" teaser, a subtle
before/after A/B on a locked feature, a first-run tour that ends on the AutoEq library.

### P4 — Instrument the funnel
We're flying on Sales Reports alone. Add lightweight local counters (paywall views, feature-gate hits,
purchases) so we can compute *paywall-view → buy*, not just *download → buy*.

---

## What NOT to do yet
- Don't discount or change the $9.99 price — conversion is healthy; the problem is volume.
- Don't build the next app yet (chose to deepen first) — but keep `docs/NEXT-APPS.md` warm.
- Don't over-engineer the paywall — n=1 sale; optimizing it now is fitting noise.

## Definition of "deepened"
Downloads ≥ ~10/day, ≥ 10 ratings (≥ 4.0★), funnel instrumented, and the review + ASO changes shipped in a
version bump. Then re-pull the funnel and decide: keep pushing Sonance, or start app #2.
