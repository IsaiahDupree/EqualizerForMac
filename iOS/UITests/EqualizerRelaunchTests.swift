import XCTest

final class EqualizerRelaunchTests: XCTestCase {
    @MainActor
    func testNamedPresetCanBeSavedAndLoadedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Presets"].tap()
        app.buttons["Vocal"].tap()
        let preamp = app.sliders["eqPreamp"]
        reveal(preamp, in: app)
        preamp.adjust(toNormalizedSliderPosition: 0.3)
        let level = try XCTUnwrap(preamp.value as? String)
        XCTAssertNotEqual(level, "0.0 dB")

        let presets = app.buttons["Presets"]
        reveal(presets, in: app, down: false)
        presets.tap()
        app.buttons["Preset Library"].tap()
        app.buttons["saveCurrentPreset"].tap()
        let name = "Studio \(UUID().uuidString.prefix(5))"
        let alert = app.alerts["Save Preset"]
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        retainScreenshot("Preset Library", app)
        app.buttons["Done"].tap()
        presets.tap()
        app.buttons["Flat"].tap()

        app.terminate()
        app.launch()
        presets.tap()
        app.buttons["Preset Library"].tap()
        app.staticTexts[name].tap()
        reveal(preamp, in: app)
        XCTAssertEqual(preamp.value as? String, level)

        let outputCorrection = app.buttons["outputCorrection"]
        outputCorrection.tap()
        let picker = app.buttons["correctionPreset"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons[name].tap()
        let enabled = app.switches["applyOutputCorrection"]
        XCTAssertEqual(picker.value as? String, name)
        XCTAssertEqual(enabled.value as? String, "1")
        retainScreenshot("Output Correction", app)
        enabled.tap()
        XCTAssertEqual(enabled.value as? String, "0")
        app.terminate()
        app.launch()
        outputCorrection.tap()
        XCTAssertEqual(picker.value as? String, name)
        XCTAssertEqual(enabled.value as? String, "0")
        app.buttons["Clear Assignment"].tap()
        XCTAssertEqual(picker.value as? String, "Choose")
    }

    @MainActor
    func testBandDropdownAddsAndRemovesTheSelectedBand() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Presets"].tap()
        app.buttons["Flat"].tap()
        let selector = app.buttons["eqBandSelector"]
        let add = app.buttons["addBand"]
        let remove = app.buttons["removeBand"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(try selectedBand(selector).hasPrefix("Band 11 · "))
        retainScreenshot("Band Selector", app)

        selector.tap()
        XCTAssertTrue(app.buttons["eqBand0"].exists)
        let newBand = app.buttons["eqBand10"]
        XCTAssertTrue(newBand.exists)
        retainScreenshot("Band Dropdown", app)
        newBand.tap()
        remove.tap()
        XCTAssertTrue(try selectedBand(selector).hasPrefix("Band 10 · "))

        selector.tap()
        XCTAssertFalse(newBand.exists)
        app.buttons["eqBand3"].tap()
        XCTAssertTrue(try selectedBand(selector).hasPrefix("Band 4 · "))
    }

    @MainActor
    func testTapSelectsAndDraggingMovesFilterOnCurve() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Presets"].tap()
        app.buttons["Flat"].tap()

        let plot = app.descendants(matching: .any)["eqResponse"].firstMatch
        XCTAssertTrue(plot.isHittable)
        let selector = app.buttons["eqBandSelector"]
        let center = plot.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: 36 + (plot.frame.width - 58) * log10(250 / 20.0) / 3,
            dy: 16 + (plot.frame.height - 42) / 2
        ))
        center.tap()
        let original = try selectedBand(selector)
        XCTAssertEqual(original, "Band 4 · 250 Hz")
        center.press(forDuration: 0.08, thenDragTo: center.withOffset(CGVector(dx: 35, dy: -33)))
        let moved = try selectedBand(selector)
        XCTAssertTrue(moved.hasPrefix("Band 4 · "))
        XCTAssertNotEqual(moved, original)
        let gain = app.sliders["eqGain"]
        reveal(gain, in: app)
        let movedGain = try XCTUnwrap(gain.value as? String)
        XCTAssertNotEqual(movedGain, "+0.0 dB")

        app.terminate()
        app.launch()
        XCTAssertEqual(try selectedBand(selector), moved)
        reveal(gain, in: app)
        XCTAssertEqual(gain.value as? String, movedGain)
    }

    @MainActor
    func testTuningAndActiveBandSurviveLeavingAndTerminatingTheApp() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.buttons["Presets"].tap()
        app.buttons["Vocal"].tap()
        let selector = app.buttons["eqBandSelector"]
        reveal(selector, in: app)
        selector.tap()
        app.buttons["eqBand3"].tap()

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
        reveal(selector, in: app)
        XCTAssertTrue(try selectedBand(selector).hasPrefix("Band 4 · "))
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
    private func selectedBand(_ selector: XCUIElement) throws -> String {
        try XCTUnwrap(selector.value as? String)
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
        let playing = NSPredicate(format: "label == %@", "Pause")
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: playing, object: transport)], timeout: 8)
        let workspace = app.segmentedControls["audioWorkspace"]
        workspace.buttons["Live"].tap()
        XCTAssertTrue(app.staticTexts["spectrumPeak"].waitForExistence(timeout: 4))
        retainScreenshot("Live Audio", app)
        workspace.buttons["Equalizer"].tap()
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(transport.isHittable)
        transport.tap()
        XCTAssertEqual(transport.label, "Play")
        XCTAssertTrue(app.buttons["stopAudio"].isHittable)
        transport.tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: playing, object: transport)], timeout: 8)

        let floatingCurve = app.buttons["floatingCurve"]
        if floatingCurve.exists {
            let ready = NSPredicate { _, _ in floatingCurve.isHittable && floatingCurve.isEnabled }
            await fulfillment(of: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5)
            floatingCurve.tap()
            let opened = NSPredicate(format: "label == %@", "Close Picture in Picture")
            await fulfillment(of: [XCTNSPredicateExpectation(predicate: opened, object: floatingCurve)], timeout: 8)
            floatingCurve.tap()
        }

        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(4))
        XCTAssertEqual(app.state, .runningBackground)
        app.activate()
        XCTAssertEqual(transport.label, "Pause")

        app.terminate()
        app.launch()
        XCTAssertEqual(transport.label, "Play")
        XCTAssertFalse(transport.isEnabled)
    }

    @MainActor
    private func retainScreenshot(_ title: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func reveal(_ item: XCUIElement, in app: XCUIApplication, down: Bool = true) {
        func visibleInEditor() -> Bool {
            guard item.isHittable else { return false }
            let abovePlayer = item.frame.maxY < app.buttons["playAudio"].frame.minY - 10
            return abovePlayer && item.frame.minY > app.navigationBars.firstMatch.frame.maxY
        }
        for _ in 0..<5 where !visibleInEditor() {
            let scroll = app.scrollViews.firstMatch
            if down { scroll.swipeUp(velocity: .slow) } else { scroll.swipeDown(velocity: .slow) }
        }
        XCTAssertTrue(visibleInEditor(), item.debugDescription)
    }
}
