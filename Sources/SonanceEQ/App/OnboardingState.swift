import Foundation

/// Tracks whether the user has completed the first-run welcome flow (what Sonance EQ does + the
/// one-time Audio Capture permission it needs). Persisted like `ReviewPrompter` so it survives
/// relaunch but only shows once.
@MainActor
@Observable
final class OnboardingState {
    private(set) var hasCompleted: Bool
    private let defaults: UserDefaults
    private let kKey = "onboarding.completedV1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompleted = defaults.bool(forKey: kKey)
    }

    func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        defaults.set(true, forKey: kKey)
    }
}
