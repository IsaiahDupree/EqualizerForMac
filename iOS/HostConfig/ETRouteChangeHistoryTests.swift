import XCTest

final class ETRouteChangeHistoryTests: XCTestCase {
    func testRouteWarningRemainsVisibleWhenHostPeerIsConnectedButOutputBypassesEQ() {
        XCTAssertTrue(ETRouteStatusPresentation.shouldDisplayBanner(
            hasPeer: true,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: true,
            routeChangeBurst: false))
        XCTAssertTrue(ETRouteStatusPresentation.shouldDisplayBanner(
            hasPeer: true,
            routeFallback: true,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: false))
    }

    func testLocalPlayerRecoveryIsOfferedForGenericRouteBurstButNotRestartGate() {
        XCTAssertTrue(ETRouteStatusPresentation.shouldOfferLocalPlayerRecovery(
            restartNeeded: false,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: true))
        XCTAssertFalse(ETRouteStatusPresentation.shouldOfferLocalPlayerRecovery(
            restartNeeded: true,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: true))
        XCTAssertFalse(ETRouteStatusPresentation.shouldOfferLocalPlayerRecovery(
            restartNeeded: false,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: false))
    }

    func testLocalPlayerRecoveryIsOfferedWhenNoAudioHasReachedTheHost() {
        XCTAssertTrue(ETRouteStatusPresentation.shouldOfferLocalPlayerRecovery(
            restartNeeded: false,
            noAudioAvailable: true,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: false))
        XCTAssertFalse(ETRouteStatusPresentation.shouldOfferLocalPlayerRecovery(
            restartNeeded: true,
            noAudioAvailable: true,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: false))
    }

    func testThreeTransitionsWithinWindowAreABurst() {
        var history = ETRouteChangeHistory()
        history.record(from: "EffectDeck", to: "CarPlay", reason: "old device unavailable", at: 100)
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "output override", at: 110)
        history.record(from: "iPhone Speaker", to: "EffectDeck", reason: "new device available", at: 120)

        XCTAssertTrue(history.isBurst)
        XCTAssertEqual(history.summary.components(separatedBy: "\n").count, 3)
    }

    func testCarPlayAndIPhoneSpeakerBounceIsClassifiedFromEndpointTypes() {
        var history = ETRouteChangeHistory()
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "old device unavailable", at: 100,
                       fromIsCarAudio: true, toIsCarAudio: false,
                       fromIsBuiltInSpeaker: false, toIsBuiltInSpeaker: true)
        history.record(from: "iPhone Speaker", to: "CarPlay", reason: "new device available", at: 105,
                       fromIsCarAudio: false, toIsCarAudio: true,
                       fromIsBuiltInSpeaker: true, toIsBuiltInSpeaker: false)
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "route configuration changed", at: 110,
                       fromIsCarAudio: true, toIsCarAudio: false,
                       fromIsBuiltInSpeaker: false, toIsBuiltInSpeaker: true)

        XCTAssertTrue(history.isCarAudioSpeakerBounce)
        let presentation = ETRouteStatusPresentation.make(
            restartNeeded: false,
            deviceName: "iPhone",
            currentRoute: "iPhone Speaker",
            routeFallback: true,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: true,
            lastRouteChange: history.summary,
            carAudioSpeakerBounce: history.isCarAudioSpeakerBounce)
        XCTAssertEqual(presentation.title, "CarPlay and iPhone output keep switching")
        XCTAssertTrue(presentation.instruction.contains("does not support EffectDeck Audio or Sonance EQ Audio"))
        XCTAssertTrue(presentation.instruction.contains("Leave CarPlay selected"))
        XCTAssertTrue(ETRouteStatusPresentation.shouldDisplayBanner(
            hasPeer: true,
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: false,
            carAudioSpeakerBounce: history.isCarAudioSpeakerBounce))
    }

    func testNonCarPlayRouteChangesDoNotClaimCarPlaySpeakerBounce() {
        var history = ETRouteChangeHistory()
        history.record(from: "Bluetooth headphones", to: "iPhone Speaker", reason: "change", at: 100,
                       toIsBuiltInSpeaker: true)
        history.record(from: "iPhone Speaker", to: "Bluetooth headphones", reason: "change", at: 105,
                       fromIsBuiltInSpeaker: true)
        history.record(from: "Bluetooth headphones", to: "iPhone Speaker", reason: "change", at: 110,
                       toIsBuiltInSpeaker: true)

        XCTAssertFalse(history.isCarAudioSpeakerBounce)
    }

    func testCarPlayAndSonanceEQHandoffsAreDetectedSeparately() throws {
        var history = ETRouteChangeHistory()
        history.record(from: "CarPlay", to: "Sonance EQ", reason: "old device unavailable", at: 100,
                       fromIsCarAudio: true, toIsEQRoute: true)
        history.record(from: "Sonance EQ", to: "CarPlay", reason: "new device available", at: 105,
                       toIsCarAudio: true, fromIsEQRoute: true)
        history.record(from: "CarPlay", to: "Sonance EQ", reason: "route configuration changed", at: 110,
                       fromIsCarAudio: true, toIsEQRoute: true)

        XCTAssertTrue(history.isCarAudioEQBounce)
        XCTAssertFalse(history.isCarAudioSpeakerBounce)
        let presentation = ETRouteStatusPresentation.make(
            restartNeeded: false,
            deviceName: "iPhone",
            currentRoute: "Sonance EQ",
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: true,
            lastRouteChange: history.summary,
            carAudioEQBounce: history.isCarAudioEQBounce)
        XCTAssertEqual(presentation.title, "CarPlay and Sonance EQ keep switching")
        XCTAssertTrue(presentation.instruction.contains("Keep CarPlay selected"))
        XCTAssertTrue(presentation.instruction.contains("does not support EffectDeck Audio or Sonance EQ Audio"))

        let suiteName = "SonanceEQ.carAudioEQBounceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try XCTUnwrap(history.encoded), forKey: ETRouteChangeHistory.storageKey)
        let restored = ETRouteChangeHistory(
            restoring: defaults.data(forKey: ETRouteChangeHistory.storageKey), at: 120)
        XCTAssertTrue(restored.isCarAudioEQBounce)
    }

    func testCarPlayEQBounceThroughBuiltInSpeakerIsDetected() {
        var history = ETRouteChangeHistory()
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "old device unavailable", at: 100,
                       fromIsCarAudio: true, toIsBuiltInSpeaker: true)
        history.record(from: "iPhone Speaker", to: "EffectDeck", reason: "new device available", at: 105,
                       fromIsBuiltInSpeaker: true, toIsEQRoute: true)
        history.record(from: "EffectDeck", to: "CarPlay", reason: "route configuration changed", at: 110,
                       toIsCarAudio: true, fromIsEQRoute: true)

        XCTAssertTrue(history.isCarAudioEQBounce)
    }

    func testCarPlayEQClassificationRequiresConnectedTransitions() {
        var history = ETRouteChangeHistory()
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "change", at: 100,
                       fromIsCarAudio: true, toIsBuiltInSpeaker: true)
        history.record(from: "unrelated route", to: "EffectDeck", reason: "change", at: 105,
                       toIsEQRoute: true)
        history.record(from: "EffectDeck", to: "CarPlay", reason: "change", at: 110,
                       toIsCarAudio: true, fromIsEQRoute: true)

        XCTAssertFalse(history.isCarAudioEQBounce)
    }

    func testOlderPersistedRouteHistoryStillLoads() {
        let legacy = Data(#"[{"uptime":100,"text":"CarPlay → iPhone Speaker (route change)","carAudioSpeakerSwap":true,"carAudioEQSwap":false}]"#.utf8)
        let history = ETRouteChangeHistory(restoring: legacy, at: 101)

        XCTAssertEqual(history.summary, "CarPlay → iPhone Speaker (route change)")
        XCTAssertFalse(history.isCarAudioEQBounce)
    }

    func testTransitionsExpireAfterThirtySeconds() {
        var history = ETRouteChangeHistory()
        history.record(from: "EffectDeck", to: "CarPlay", reason: "route change", at: 100)
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "route change", at: 101)
        history.record(from: "iPhone Speaker", to: "EffectDeck", reason: "route change", at: 102)

        history.expire(at: 132.01)

        XCTAssertFalse(history.isBurst)
        XCTAssertEqual(history.summary, "")
    }

    func testSummaryShowsLastFourButBurstCountsEveryRecentTransition() {
        var history = ETRouteChangeHistory()
        for index in 1...6 {
            history.record(from: "route\(index)", to: "route\(index + 1)", reason: "change", at: Double(index))
        }

        XCTAssertTrue(history.isBurst)
        XCTAssertEqual(history.summary.components(separatedBy: "\n").count, 4)
        XCTAssertTrue(history.summary.hasPrefix("route3 → route4"))
        XCTAssertTrue(history.summary.hasSuffix("route6 → route7 (change)"))
    }

    func testExactlyThirtySecondsRemainsInWindow() {
        var history = ETRouteChangeHistory()
        history.record(from: "A", to: "B", reason: "change", at: 100)

        history.expire(at: 130)
        XCTAssertEqual(history.summary, "A → B (change)")

        history.expire(at: 130.001)
        XCTAssertEqual(history.summary, "")
    }

    func testRouteEvidenceSurvivesProcessRelaunchWithinTheDiagnosticWindow() throws {
        var history = ETRouteChangeHistory()
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "old device unavailable", at: 100,
                       fromIsCarAudio: true, toIsCarAudio: false,
                       fromIsBuiltInSpeaker: false, toIsBuiltInSpeaker: true)
        history.record(from: "iPhone Speaker", to: "CarPlay", reason: "new device available", at: 105,
                       fromIsCarAudio: false, toIsCarAudio: true,
                       fromIsBuiltInSpeaker: true, toIsBuiltInSpeaker: false)
        history.record(from: "CarPlay", to: "iPhone Speaker", reason: "route configuration changed", at: 110,
                       fromIsCarAudio: true, toIsCarAudio: false,
                       fromIsBuiltInSpeaker: false, toIsBuiltInSpeaker: true)

        let suiteName = "SonanceEQ.routeHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try XCTUnwrap(history.encoded), forKey: ETRouteChangeHistory.storageKey)

        let storedData = try XCTUnwrap(defaults.data(forKey: ETRouteChangeHistory.storageKey))
        let restored = ETRouteChangeHistory(restoring: storedData, at: 120)
        XCTAssertEqual(restored.summary, history.summary)
        XCTAssertTrue(restored.isBurst)
        XCTAssertTrue(restored.isCarAudioSpeakerBounce)

        let expired = ETRouteChangeHistory(restoring: storedData, at: 140.001)
        XCTAssertEqual(expired.summary, "")
        XCTAssertFalse(expired.isBurst)
    }

    func testBurstWarningTakesPriorityOverSingleRouteReturn() {
        let presentation = ETRouteStatusPresentation.make(
            restartNeeded: false,
            deviceName: "iPhone",
            currentRoute: "CarPlay",
            routeFallback: false,
            routeReturnedFromSonanceEQ: true,
            carAudioActive: true,
            routeChangeBurst: true,
            lastRouteChange: "EffectDeck → CarPlay (old device unavailable)\nCarPlay → iPhone Speaker (output override)")

        XCTAssertEqual(presentation.title, "Audio route keeps changing")
        XCTAssertTrue(presentation.instruction.contains("Recent changes:"))
        XCTAssertTrue(presentation.instruction.contains("Stop toggling between routes"))
        XCTAssertTrue(presentation.instruction.contains("CarPlay selected (EQ is bypassed)"))
    }

    func testSingleRouteReturnIdentifiesSourceRejectionAndSafeRecovery() {
        let presentation = ETRouteStatusPresentation.make(
            restartNeeded: false,
            deviceName: "iPhone",
            currentRoute: "CarPlay",
            routeFallback: false,
            routeReturnedFromSonanceEQ: true,
            carAudioActive: true,
            routeChangeBurst: false,
            lastRouteChange: "EffectDeck → CarPlay (old device unavailable)")

        XCTAssertEqual(presentation.title, "Audio left the EQ route for CarPlay")
        XCTAssertTrue(presentation.instruction.contains("does not mean the EQ is faulty"))
        XCTAssertTrue(presentation.instruction.contains("EffectDeck Audio"))
        XCTAssertTrue(presentation.instruction.contains("compatible player / local file for EQ"))
    }

    func testDirectCarAudioIsIdentifiedAsBypassingTheEQ() {
        let presentation = ETRouteStatusPresentation.make(
            restartNeeded: false,
            deviceName: "iPhone",
            currentRoute: "CarPlay",
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: true,
            routeChangeBurst: false,
            lastRouteChange: "")

        XCTAssertEqual(presentation.title, "Output is routed to car audio")
        XCTAssertTrue(presentation.instruction.contains("bypasses Sonance EQ"))
    }

    func testRouteReportContainsOnlyRouteStateAndAppVersions() {
        let report = ETRouteDiagnosticReport.make(
            appVersion: "0.2.0",
            build: "34",
            osVersion: "27.3",
            currentOutput: "CarPlay",
            routeFallback: true,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: true,
            routeChangeBurst: true,
            carAudioSpeakerBounce: true,
            carAudioEQBounce: false,
            recentChanges: "CarPlay → iPhone Speaker (old device unavailable)")

        XCTAssertTrue(report.contains("App: 0.2.0 (34)"))
        XCTAssertTrue(report.contains("iOS: 27.3"))
        XCTAssertTrue(report.contains("Current output: CarPlay"))
        XCTAssertTrue(report.contains("CarPlay → iPhone Speaker (old device unavailable)"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("track"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("audio sample"))
    }

    func testRouteReportMarksUnavailableOutputAndTransitionHistory() {
        let report = ETRouteDiagnosticReport.make(
            appVersion: "0.2.0",
            build: "34",
            osVersion: "27.3",
            currentOutput: "—",
            routeFallback: false,
            routeReturnedFromSonanceEQ: false,
            carAudioActive: false,
            routeChangeBurst: false,
            carAudioSpeakerBounce: false,
            carAudioEQBounce: false,
            recentChanges: "  ")

        XCTAssertTrue(report.contains("Current output: Unknown"))
        XCTAssertTrue(report.contains("Recent route changes:\nNone recorded"))
    }
}
