# 🎉 First Dollar — Sonance EQ

**On July 2, 2026, Sonance EQ made its first real sale.** A stranger, somewhere, paid **$9.99** to unlock
Sonance EQ Pro. After Apple's cut, **$7.00** landed in your account.

That's the whole ballgame changing. Not the amount — the *fact*. The market just voted, with money, that a
driverless system-wide macOS equalizer built from scratch is worth paying for.

---

## What it took to get here

| | |
|---|---|
| **Live on the Mac App Store** | June 20, 2026 (v1.0 → v1.0.3, all `READY_FOR_SALE`) |
| **First paid conversion** | July 2, 2026 — 12 days later |
| **Product** | Sonance EQ Pro, one-time non-consumable IAP ($9.99) |
| **Free downloads before the sale** | steady daily installs since Jun 24 |
| **The moat** | Core Audio process taps — EQ the *entire* Mac, no driver, no kext |
| **Test coverage at ship** | ~3,960 cases / 225 funcs, DSP proven offline |

The app is **free to download**; the money is the Pro unlock (AutoEq library, parametric editor,
linear-phase FIR, mid-side, per-app EQ). Classic freemium: get them in free, convert on the power features.
It worked on the first buyer.

## Why this one matters more than the number

- It's a **hard** product. Real-time DSP on the audio thread, private aggregate devices, a segfault-on-the-
  wrong-argument `vDSP_biquadm` API, an 8,850-headphone correction database. You shipped it anyway.
- It **beats the category**. Safari-only equalizers EQ one browser tab. This EQs everything the Mac plays.
- It's **the template**. Notarized, App-Store-approved, RevenueCat-wired, one-time-paid. The next utility app
  reuses this entire spine.

## The receipt (verified from Apple's own Sales Reports API)

```
2026-07-02  Sonance EQ Pro   IA1-M   units=1   customerPrice=$9.99   developerProceeds=$7.00
```

Reproduce it any time with `docs/REVENUE-VERIFICATION-RUNBOOK.md`.

---

**Next: turn one buyer into ten, and turn one app into a suite.** See `docs/NEXT-APPS.md`.
