import Foundation

/// Asks for an App Store rating after a few **positive** interactions (applying a preset, loading a
/// headphone correction) — never on first launch, never on a paywall bounce. This is our first-sale
/// growth lever: 0 ratings hurts ranking + trust, and happy users only rate if asked at the right moment.
///
/// Apple already rate-limits the real prompt (≤3/year). We additionally cap to **once per app version** and
/// gate on `threshold` positive actions, so the ask lands after the app has demonstrably helped the user.
/// The root view installs `present` from the SwiftUI `@Environment(\.requestReview)` action (macOS 13+);
/// it stays a no-op until then, and tests inject their own closure to exercise the decision logic.
@MainActor
final class ReviewPrompter {
    private let defaults: UserDefaults
    private let version: String
    let threshold: Int

    /// Installed by the root view from `@Environment(\.requestReview)`. No-op until then; overridable in tests.
    var present: () -> Void = {}

    private let kCount = "review.positiveActions"
    private let kPromptedVersion = "review.lastPromptedVersion"

    init(defaults: UserDefaults = .standard,
         version: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?",
         threshold: Int = 4) {
        self.defaults = defaults
        self.version = version
        self.threshold = threshold
    }

    /// Record a positive moment; may present the rating prompt. Returns `true` iff it presented this call.
    @discardableResult
    func positiveAction() -> Bool {
        let count = defaults.integer(forKey: kCount) + 1
        defaults.set(count, forKey: kCount)
        guard count >= threshold,
              defaults.string(forKey: kPromptedVersion) != version else { return false }
        defaults.set(version, forKey: kPromptedVersion)
        present()
        return true
    }
}
