import XCTest

final class EqualizerRelaunchTests: XCTestCase {
    @MainActor
    func testTuningAndActiveBandSurviveLeavingAndTerminatingTheApp() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.buttons["Presets"].tap()
        app.buttons["Vocal"].tap()
        let band = app.buttons["eqBand3"]
        reveal(band, in: app)
        band.tap()

        let positions: [(String, CGFloat)] = [("eqFrequency", 0.51), ("eqGain", 0.75),
                                             ("eqQuality", 0.40), ("eqPreamp", 0.24)]
        var changed: [String: String] = [:]
        for (identifier, position) in positions {
            let slider = app.sliders[identifier]
            reveal(slider, in: app)
            let before = try XCTUnwrap(slider.value as? String)
            slider.adjust(toNormalizedSliderPosition: position)
            let after = try XCTUnwrap(slider.value as? String)
            XCTAssertNotEqual(after, before, identifier)
            changed[identifier] = after
        }

        let bypass = app.switches["bypassEQ"]
        reveal(bypass, in: app, down: false)
        let originalBypass = try XCTUnwrap(bypass.value as? String)
        bypass.tap()
        let changedBypass = try XCTUnwrap(bypass.value as? String)
        XCTAssertNotEqual(changedBypass, originalBypass)

        // Check a completed edit immediately after a fresh process launch.
        app.terminate()
        app.launch()

        XCTAssertEqual(bypass.value as? String, changedBypass)
        XCTAssertEqual(app.buttons["playAudio"].label, "Play")
        XCTAssertFalse(app.buttons["playAudio"].isEnabled)
        reveal(band, in: app)
        XCTAssertTrue(band.isSelected)
        for (identifier, _) in positions {
            let slider = app.sliders[identifier]
            reveal(slider, in: app)
            XCTAssertEqual(slider.value as? String, changed[identifier], identifier)
        }

        XCUIDevice.shared.press(.home)
        let backgrounded = NSPredicate { _, _ in
            [.runningBackground, .runningBackgroundSuspended].contains(app.state)
        }
        wait(for: [XCTNSPredicateExpectation(predicate: backgrounded, object: nil)], timeout: 6)
        app.activate()
        XCTAssertEqual(bypass.value as? String, changedBypass)
    }

    @MainActor
    func testLocalPlaybackContinuesOnHomeScreenAndStopsOnTermination() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["openAudio"].tap()

        let elements = app.descendants(matching: .any)
        let fixture = elements.matching(NSPredicate(format: "label IN %@",
            ["Sonance Background Verification", "Sonance Background Verification.wav"])).firstMatch
        if !fixture.exists {
            let location = elements.matching(NSPredicate(format: "label IN %@", ["On My iPhone", "On My iPad"])).firstMatch
            if !location.exists {
                let browse = elements.matching(NSPredicate(format: "label == %@", "Browse")).firstMatch
                if browse.waitForExistence(timeout: 5), browse.isHittable { browse.tap() }
            }
            if location.waitForExistence(timeout: 5), location.isHittable { location.tap() }
        }
        try XCTSkipUnless(fixture.waitForExistence(timeout: 5),
                          "Place Sonance Background Verification.wav in On My iPhone to run this case.")
        let tile = app.cells.containing(.staticText, identifier: fixture.label).firstMatch
        if tile.exists, tile.isHittable {
            tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)).tap()
        } else {
            fixture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -28)).tap()
        }

        let transport = app.buttons["playAudio"]
        let ready = NSPredicate { _, _ in transport.exists && transport.isHittable && transport.isEnabled }
        let opened = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10)
        guard opened == .completed else {
            add(XCTAttachment(screenshot: app.screenshot()))
            XCTFail("Files did not return a playable audio file.")
            return
        }
        transport.tap()
        let playing = NSPredicate(format: "label == %@", "Stop")
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: playing, object: transport)], timeout: 8)

        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(4))
        XCTAssertEqual(app.state, .runningBackground)
        app.activate()
        XCTAssertEqual(transport.label, "Stop")

        app.terminate()
        app.launch()
        XCTAssertEqual(transport.label, "Play")
        XCTAssertFalse(transport.isEnabled)
    }

    @MainActor
    private func reveal(_ item: XCUIElement, in app: XCUIApplication, down: Bool = true) {
        for _ in 0..<5 where !item.isHittable {
            if down { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(item.isHittable, item.debugDescription)
    }
}
