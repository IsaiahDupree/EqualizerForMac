import XCTest

final class EqualizerRelaunchTests: XCTestCase {
    @MainActor
    func testEditorUndoAndRedoRestorePresetChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Presets"].tap()
        app.buttons["Flat"].tap()
        let preamp = app.sliders["eqPreamp"]
        reveal(preamp, in: app)
        let initial = try XCTUnwrap(preamp.value as? String)

        app.buttons["Presets"].tap()
        app.buttons["Vocal"].tap()
        let undo = app.buttons["undoEQ"]
        let redo = app.buttons["redoEQ"]
        XCTAssertTrue(undo.isEnabled)
        XCTAssertNotEqual(preamp.value as? String, initial)

        undo.tap()
        XCTAssertEqual(preamp.value as? String, initial)
        XCTAssertTrue(redo.isEnabled)

        redo.tap()
        XCTAssertNotEqual(preamp.value as? String, initial)
        XCTAssertTrue(undo.isEnabled)
    }

    @MainActor
    func testAutoEqProfileCanBeSearchedAndAssignedToOutput() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        app.buttons["Presets"].tap()
        app.buttons["Headphone Correction Library"].tap()
        let search = app.textFields["headphoneCatalogSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("AirPods Pro 3")

        let preset = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "headphonePreset-"
        )).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertTrue(preset.label.localizedCaseInsensitiveContains("AirPods Pro 3"))

        app.buttons["headphonePresetActions"].firstMatch.tap()
        let assign = app.buttons["Assign as Output Correction"]
        XCTAssertTrue(assign.waitForExistence(timeout: 5))
        XCTAssertTrue(assign.isEnabled, "The simulator must expose one current output for assignment.")
        assign.tap()

        app.buttons["outputCorrection"].tap()
        let correctionPreset = app.buttons["correctionPreset"]
        XCTAssertTrue(correctionPreset.waitForExistence(timeout: 5))
        XCTAssertTrue((correctionPreset.value as? String)?.localizedCaseInsensitiveContains("AirPods Pro 3") == true)
        let applyCorrection = app.buttons["applyOutputCorrection"]
        XCTAssertEqual(applyCorrection.value as? String, "On")

        app.buttons["Clear Assignment"].tap()
        app.buttons["Done"].tap()
    }

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
        XCTAssertEqual(field.value as? String, name)
        alert.buttons["Save"].tap()
        retainScreenshot("Preset Library After Save", app)
        let savedPreset = app.buttons["savedPreset-\(name)"]
        reveal(savedPreset, in: app, presetRow: true)
        retainScreenshot("Preset Library", app)
        app.buttons["Done"].tap()
        presets.tap()
        app.buttons["Flat"].tap()

        app.terminate()
        app.launch()
        presets.tap()
        app.buttons["Preset Library"].tap()
        let restoredPreset = app.buttons["savedPreset-\(name)"]
        reveal(restoredPreset, in: app, presetRow: true)
        restoredPreset.tap()
        reveal(preamp, in: app)
        XCTAssertEqual(preamp.value as? String, level)

        let outputCorrection = app.buttons["outputCorrection"]
        outputCorrection.tap()
        let picker = app.buttons["correctionPreset"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons[name].tap()
        let enabled = app.buttons["applyOutputCorrection"]
        XCTAssertEqual(picker.value as? String, name)
        XCTAssertEqual(enabled.value as? String, "On")
        retainScreenshot("Output Correction", app)
        enabled.tap()
        let disabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (enabled.value as? String) == "Off" },
            object: nil
        )
        retainScreenshot("Output Correction After Toggle", app)
        XCTAssertEqual(XCTWaiter.wait(for: [disabledExpectation], timeout: 3), .completed)
        app.terminate()
        app.launch()
        outputCorrection.tap()
        XCTAssertEqual(picker.value as? String, name)
        XCTAssertEqual(enabled.value as? String, "Off")
        app.buttons["Clear Assignment"].tap()
        XCTAssertEqual(picker.value as? String, "Choose")
        app.buttons["Done"].tap()
        presets.tap()
        app.buttons["Preset Library"].tap()
        let presetActions = app.buttons["Actions for \(name)"]
        revealPresetActions(presetActions, in: app)
        presetActions.tap()
        app.buttons["Delete Preset"].tap()
        app.buttons["Delete Preset"].tap()
        XCTAssertFalse(app.buttons["savedPreset-\(name)"].exists)
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

        let restoredBypass = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", changedBypass),
            object: bypass
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restoredBypass], timeout: 5), .completed)
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
        app.launchArguments.append("--sonance-ui-test-playback-fixture")
        app.launch()
        let openAudio = app.buttons["openAudio"]
        let fixtureSelected = NSPredicate { _, _ in
            (openAudio.value as? String)?.contains("SonanceBackgroundVerification.wav") == true
        }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: fixtureSelected, object: openAudio)], timeout: 8)

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
        let playbackPosition = app.sliders["playbackPosition"]
        XCTAssertTrue(playbackPosition.waitForExistence(timeout: 4))
        playbackPosition.adjust(toNormalizedSliderPosition: 0.4)
        XCTAssertTrue(playbackPosition.exists, "The playback scrubber should remain available after a seek.")
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
        app.launchArguments = []
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
    private func reveal(_ item: XCUIElement, in app: XCUIApplication, down: Bool = true,
                        presetRow: Bool = false) {
        func visibleInEditor() -> Bool {
            guard item.exists, item.isHittable else { return false }
            if presetRow {
                return item.frame.minY > app.navigationBars.firstMatch.frame.maxY
            }
            let abovePlayer = item.frame.maxY < app.buttons["playAudio"].frame.minY - 10
            return abovePlayer && item.frame.minY > app.navigationBars.firstMatch.frame.maxY
        }
        let list = app.collectionViews.firstMatch
        var attempts = 0
        while !visibleInEditor() && attempts < 8 {
            attempts += 1
            if presetRow && list.exists {
                let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.8 : 0.25))
                let to = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.25 : 0.8))
                from.press(forDuration: 0.1, thenDragTo: to)
            } else if down {
                app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            } else {
                app.scrollViews.firstMatch.swipeDown(velocity: .slow)
            }
        }
        XCTAssertTrue(visibleInEditor(), "Expected the requested control to be visible and hittable.")
    }

    @MainActor
    private func revealPresetActions(_ item: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        var attempts = 0
        while (!item.exists || !item.isHittable) && attempts < 8 {
            attempts += 1
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        XCTAssertTrue(item.exists && item.isHittable, "Expected the saved preset actions to be visible.")
    }
}
