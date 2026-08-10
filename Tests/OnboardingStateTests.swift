import Foundation
import Testing
@testable import SonanceEQ

@MainActor
@Suite struct OnboardingStateTests {
    private func fresh() -> OnboardingState {
        OnboardingState(defaults: UserDefaults(suiteName: "test.onboarding.\(UUID().uuidString)")!)
    }

    @Test func notCompletedByDefault() {
        #expect(!fresh().hasCompleted)
    }

    @Test func completeSetsFlag() {
        let state = fresh()
        state.complete()
        #expect(state.hasCompleted)
    }

    @Test func completionPersistsAcrossInstances() {
        let suite = UserDefaults(suiteName: "test.onboarding.\(UUID().uuidString)")!
        OnboardingState(defaults: suite).complete()
        #expect(OnboardingState(defaults: suite).hasCompleted)
    }
}
