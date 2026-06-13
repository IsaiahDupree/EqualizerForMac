import Foundation

/// Central, M3-fillable licensing configuration. Every RevenueCat / App Store identifier lives here
/// so wiring the real account in M3 is a config edit — not a code change.
///
/// RevenueCat **public** SDK keys are designed to be embedded in the app binary (they are not secrets),
/// so hardcoding them here is correct per RevenueCat's docs. The *secret* server key (used by the
/// `revenuecat-mcp` tooling) never ships in the app.
enum LicenseConfig {
    /// RevenueCat public SDK key. Direct (Developer ID) and Mac App Store builds map to **different**
    /// RevenueCat "apps" → different public keys; select per build in M3. Until then this sentinel keeps
    /// the app fully unlocked with no network calls (see `PurchaseManager.start()`).
    static let revenueCatPublicAPIKey = unconfiguredSentinel

    /// Entitlement that unlocks Pro. Create in the RevenueCat dashboard in M3.
    static let proEntitlementID = "pro"

    /// Offering whose packages the paywall shows. "default" is RevenueCat's current-offering convention.
    static let offeringID = "default"

    /// One-time, non-consumable unlock. Create in App Store Connect (M3), then attach in RevenueCat.
    static let proProductID = "com.isaiahdupree.SonanceEQ.pro"

    /// Sentinel meaning "no real RevenueCat account wired yet" → dev/eval builds stay unlocked.
    static let unconfiguredSentinel = "REVENUECAT_PUBLIC_KEY_TODO"

    /// True until a real public key is filled in.
    static var isUnconfigured: Bool { revenueCatPublicAPIKey == unconfiguredSentinel }
}

/// Pro-gated capabilities. Free tier = the M1 10-band graphic EQ + built-in presets.
/// Pro unlocks the differentiators. Change the gating in one place: `PurchaseManager.canUse(_:)`.
enum ProFeature: CaseIterable {
    case parametricEQ    // M2 — vDSP_biquadm 32-band parametric engine
    case autoEqLibrary   // M2 — 8,850-headphone AutoEq correction database
    case importExport    // M2 — preset import/export
    case perAppEQ        // M3 — per-application equalization
}
