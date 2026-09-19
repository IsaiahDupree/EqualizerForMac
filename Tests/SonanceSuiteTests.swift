import Testing
@testable import SonanceEQ

@Suite struct SonanceSuiteTests {
    @Test func eachAppLinksToThreeDistinctSiblings() {
        for current in SonanceSuiteApp.allCases {
            let siblings = SonanceSuite.siblings(of: current)
            #expect(siblings.count == 3)
            #expect(!siblings.contains(current))
            #expect(Set(siblings.map(\.appStoreID)).count == 3)
        }
    }

    @Test func linksUseCanonicalAppStoreIDs() {
        #expect(SonanceSuiteApp.eq.appStoreURL.absoluteString == "https://apps.apple.com/app/id6782463839")
        #expect(SonanceSuiteApp.mixer.appStoreID == "6787488996")
        #expect(SonanceSuiteApp.recorder.appStoreID == "6787489259")
        #expect(SonanceSuiteApp.voice.appStoreID == "6787489282")
    }
}
