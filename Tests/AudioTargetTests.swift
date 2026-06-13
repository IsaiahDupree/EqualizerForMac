import Foundation
import Testing
@testable import SonanceEQ

@Suite struct EQTargetTests {
    @Test func allAppsFlag() {
        #expect(EQTarget.allApps.isAllApps)
        #expect(!EQTarget.apps(["com.apple.Music"]).isAllApps)
    }

    @Test func equatable() {
        #expect(EQTarget.apps(["a", "b"]) == EQTarget.apps(["b", "a"]))
        #expect(EQTarget.allApps != EQTarget.apps(["a"]))
    }
}

@MainActor
@Suite struct PerAppTargetTests {
    @Test func defaultsToAllApps() {
        let app = AppState()
        #expect(app.eqTarget.isAllApps)
        #expect(app.targetLabel == "All Apps")
    }

    @Test func togglingSelectsAnApp() {
        let app = AppState()
        app.toggleApp("com.apple.Music")
        #expect(app.isAppSelected("com.apple.Music"))
        #expect(app.eqTarget == .apps(["com.apple.Music"]))
    }

    @Test func togglingTwiceReturnsToAllApps() {
        let app = AppState()
        app.toggleApp("com.example.x")
        app.toggleApp("com.example.x")
        #expect(app.eqTarget.isAllApps)
    }

    @Test func setAllAppsClearsSelection() {
        let app = AppState()
        app.toggleApp("com.example.x")
        app.setAllApps()
        #expect(app.eqTarget.isAllApps)
        #expect(!app.isAppSelected("com.example.x"))
    }

    @Test func labelCountsMultipleApps() {
        let app = AppState()
        app.toggleApp("com.a")
        app.toggleApp("com.b")
        #expect(app.targetLabel == "2 apps")
    }

    @Test func labelFallsBackToBundleIDWhenNameUnknown() {
        let app = AppState()
        app.toggleApp("com.solo")
        #expect(app.targetLabel == "com.solo")   // not in availableApps → bundle id
    }
}
