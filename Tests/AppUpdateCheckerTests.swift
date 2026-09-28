import Testing
@testable import SonanceEQ

@Suite struct AppUpdateCheckerTests {
    @Test func detectsNewerPatchVersion() {
        #expect(AppUpdateChecker.isVersion("1.0.6", newerThan: "1.0.5"))
    }

    @Test func detectsNewerMultiDigitComponent() {
        #expect(AppUpdateChecker.isVersion("1.10", newerThan: "1.9"))
    }

    @Test func doesNotOfferCurrentOrOlderVersion() {
        #expect(!AppUpdateChecker.isVersion("1.0.5", newerThan: "1.0.5"))
        #expect(!AppUpdateChecker.isVersion("1.0.4", newerThan: "1.0.5"))
    }
}
