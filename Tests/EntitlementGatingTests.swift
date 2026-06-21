import Foundation
import Testing
@testable import SonanceEQ

// MARK: - Fixtures (file scope so the @Test macro reads them outside the @MainActor suite)

/// One row of the entitlement truth table: the set of *validated, active* entitlement ids RevenueCat
/// reports for a customer, and whether that should unlock Pro.
struct EntitlementCase: Sendable {
    let active: [String]
    let unlocksPro: Bool
}

/// Pro unlocks **iff** the validated active set contains exactly "pro" (`LicenseConfig.proEntitlementID`).
/// Everything else — nothing purchased, a different/sibling entitlement, a near-miss string, wrong case —
/// must stay locked (fail-closed).
let entitlementTruthTable: [EntitlementCase] = [
    .init(active: [],                         unlocksPro: false),  // never purchased
    .init(active: ["pro"],                    unlocksPro: true),   // the real thing
    .init(active: ["pro", "premium"],         unlocksPro: true),   // pro + something else
    .init(active: ["premium", "pro", "plus"], unlocksPro: true),
    .init(active: ["premium"],                unlocksPro: false),  // a different product
    .init(active: ["plus"],                   unlocksPro: false),
    .init(active: ["trial"],                  unlocksPro: false),  // a trial that isn't the pro entitlement
    .init(active: ["premium", "plus"],        unlocksPro: false),
    .init(active: ["Pro"],                    unlocksPro: false),  // case-sensitive
    .init(active: ["PRO"],                    unlocksPro: false),
    .init(active: ["pro "],                   unlocksPro: false),  // trailing space
    .init(active: [" pro"],                   unlocksPro: false),
    .init(active: ["pro.v2"],                 unlocksPro: false),
    .init(active: ["pro_unlock"],             unlocksPro: false),
    .init(active: ["com.isaiahdupree.SonanceEQ.pro"], unlocksPro: false),  // the PRODUCT id is not the ENTITLEMENT id
    .init(active: ["sonance_pro"],            unlocksPro: false),
    .init(active: ["", "pro"],                unlocksPro: true),   // empty id alongside pro still unlocks
    .init(active: [""],                       unlocksPro: false),
    .init(active: ["proo"],                   unlocksPro: false),
    .init(active: ["pr"],                     unlocksPro: false),
]

/// Non-pro entitlement ids — none may unlock Pro, no matter which feature is asked for.
let nonProEntitlements: [String] = [
    "premium", "plus", "trial", "Pro", "PRO", "pro ", "free", "basic",
    "com.isaiahdupree.SonanceEQ.pro", "subscription", "lifetime", "proo",
]

/// All 16 subsets of a small entitlement universe (one of which is the real "pro"), for the gating matrix.
let entitlementSubsets: [[String]] = {
    let universe = ["pro", "premium", "plus", "trial"]
    return (0..<(1 << universe.count)).map { mask in
        universe.enumerated().compactMap { i, id in (mask & (1 << i)) != 0 ? id : nil }
    }
}()

// MARK: - Suite

/// The enforcement contract: **a user without a valid `pro` entitlement is blocked from every Pro
/// feature.** These tests drive `applyActiveEntitlements` / `isProActive` — the real on-device policy
/// that consumes RevenueCat's validated `CustomerInfo.entitlements.active` — so they cover the shipping
/// path, not just the mock store. (RevenueCat performs the receipt/transaction validation server-side;
/// we trust only that validated signal and fail closed.)
@MainActor
@Suite struct EntitlementGatingTests {

    // 20 rows — the pure policy resolves Pro correctly for every entitlement set.
    @Test(arguments: entitlementTruthTable)
    func isProActiveTruthTable(_ c: EntitlementCase) {
        #expect(PurchaseManager.isProActive(in: Set(c.active)) == c.unlocksPro)
    }

    // The headline guarantee: NO active entitlement ⇒ every Pro feature locked, paywall-routed.
    // 5 features.
    @Test(arguments: ProFeature.allCases)
    func unpaidUserIsBlockedFromEveryFeature(_ feature: ProFeature) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements([])              // RevenueCat reports no active entitlements
        #expect(!pm.isPro)
        #expect(!pm.canUse(feature))
        #expect(pm.indicator(for: feature) == .locked)
        #expect(pm.shouldShowPaywall(for: feature))
    }

    // A valid `pro` entitlement unlocks every feature. 5 features.
    @Test(arguments: ProFeature.allCases)
    func paidUserUnlocksEveryFeature(_ feature: ProFeature) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements(["pro"])
        #expect(pm.isPro)
        #expect(pm.canUse(feature))
        #expect(pm.indicator(for: feature) == .unlocked)
        #expect(!pm.shouldShowPaywall(for: feature))
    }

    // 12 non-pro entitlements × 5 features = 60 — holding the WRONG entitlement never unlocks anything.
    @Test(arguments: nonProEntitlements, ProFeature.allCases)
    func wrongEntitlementNeverUnlocks(_ id: String, _ feature: ProFeature) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements([id])
        #expect(!pm.isPro)
        #expect(!pm.canUse(feature))
    }

    // 16 subsets × 5 features = 80 — for ANY combination the user might hold, a feature is unlocked
    // iff and only iff the validated set contains "pro".
    @Test(arguments: entitlementSubsets, ProFeature.allCases)
    func subsetGatingMatrix(_ subset: [String], _ feature: ProFeature) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements(Set(subset))
        #expect(pm.canUse(feature) == subset.contains("pro"))
    }

    // 5 features — a revoked/expired/refunded entitlement (RevenueCat drops it from `.active`) re-locks.
    @Test(arguments: ProFeature.allCases)
    func revokedEntitlementReLocks(_ feature: ProFeature) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements(["pro"])
        #expect(pm.canUse(feature))
        pm.applyActiveEntitlements([])              // entitlement no longer active
        #expect(!pm.canUse(feature))
        #expect(pm.shouldShowPaywall(for: feature))
    }

    // 5 features — fail-closed default: a brand-new manager (nothing applied) is locked everywhere.
    @Test(arguments: ProFeature.allCases)
    func freshManagerIsLockedByDefault(_ feature: ProFeature) {
        let suite = "test.purchases.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { LicensingTestKit.dispose(suite) }
        let pm = PurchaseManager(defaults: defaults)   // not started, no entitlement
        #expect(!pm.isPro)
        #expect(!pm.canUse(feature))
    }

    // 16 subsets — applying the same validated set twice is idempotent (no toggle/flicker).
    @Test(arguments: entitlementSubsets)
    func applyIsIdempotent(_ subset: [String]) {
        let (pm, _, suite) = LicensingTestKit.makeManager()
        defer { LicensingTestKit.dispose(suite) }
        pm.applyActiveEntitlements(Set(subset))
        let first = pm.isPro
        pm.applyActiveEntitlements(Set(subset))
        #expect(pm.isPro == first)
        #expect(pm.isPro == subset.contains("pro"))
    }

    @Test func entitlementIdMatchesLicenseConfig() {
        // The policy keys off LicenseConfig.proEntitlementID — guard it stays "pro" (RevenueCat dashboard).
        #expect(LicenseConfig.proEntitlementID == "pro")
        #expect(PurchaseManager.isProActive(in: [LicenseConfig.proEntitlementID]))
        #expect(!PurchaseManager.isProActive(in: []))
    }
}
