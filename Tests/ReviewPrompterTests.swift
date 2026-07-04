import Foundation
import Testing
@testable import SonanceEQ

@MainActor
@Suite struct ReviewPrompterTests {
    private func fresh(version: String = "1.0.3", threshold: Int = 4)
        -> (ReviewPrompter, () -> Int) {
        let defaults = UserDefaults(suiteName: "test.review.\(UUID().uuidString)")!
        var presented = 0
        let p = ReviewPrompter(defaults: defaults, version: version, threshold: threshold)
        p.present = { presented += 1 }
        return (p, { presented })
    }

    @Test func doesNotPromptBeforeThreshold() {
        let (p, count) = fresh(threshold: 4)
        for _ in 0..<3 { #expect(p.positiveAction() == false) }
        #expect(count() == 0)
    }

    @Test func promptsExactlyOnceAtThreshold() {
        let (p, count) = fresh(threshold: 4)
        #expect(p.positiveAction() == false) // 1
        #expect(p.positiveAction() == false) // 2
        #expect(p.positiveAction() == false) // 3
        #expect(p.positiveAction() == true)  // 4 → prompt
        #expect(count() == 1)
    }

    @Test func doesNotPromptTwiceInSameVersion() {
        let (p, count) = fresh(threshold: 2)
        _ = p.positiveAction()
        #expect(p.positiveAction() == true)   // threshold hit → prompt
        for _ in 0..<5 { #expect(p.positiveAction() == false) } // capped for this version
        #expect(count() == 1)
    }

    @Test func promptsAgainOnNewVersion() {
        let defaults = UserDefaults(suiteName: "test.review.\(UUID().uuidString)")!
        var presented = 0
        let v1 = ReviewPrompter(defaults: defaults, version: "1.0.3", threshold: 1)
        v1.present = { presented += 1 }
        #expect(v1.positiveAction() == true)      // prompts on 1.0.3
        let v2 = ReviewPrompter(defaults: defaults, version: "1.0.4", threshold: 1)
        v2.present = { presented += 1 }
        #expect(v2.positiveAction() == true)      // new version → prompts again
        #expect(presented == 2)
    }
}
