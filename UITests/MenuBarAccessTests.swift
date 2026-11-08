import XCTest

/// Exercises the real menu bar and singleton window without starting capture or purchases.
@MainActor
final class MenuBarAccessTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.isaiahdupree.SonanceEQ.MenuBarAccessTests")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.windows["Sonance EQ"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testMenuReusesWindowAndReopensClosedWindowWithEQSettings() {
        // Load the real bundled correction, then check presentation doesn't reset it.
        app.buttons["Headphones"].click()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        app.typeText("AirPods Pro 3")
        let preset = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Apple AirPods Pro 3")
        ).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.click()
        let window = app.windows["Sonance EQ"]
        let activePreset = window.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Apple AirPods Pro 3 · Songbird")
        ).firstMatch
        XCTAssertTrue(activePreset.waitForExistence(timeout: 5))
        let curve = window.sliders.allElementsBoundByIndex.map { String(describing: $0.value) }
        XCTAssertFalse(curve.isEmpty)

        openFromMenuBar()
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(window.sliders.allElementsBoundByIndex.map { String(describing: $0.value) }, curve)
        XCTAssertTrue(activePreset.exists)
        XCTAssertTrue(app.buttons["Start EQ"].exists)

        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .notRunning)

        openFromMenuBar()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertEqual(window.sliders.allElementsBoundByIndex.map { String(describing: $0.value) }, curve)
        XCTAssertTrue(activePreset.exists)
        XCTAssertTrue(app.buttons["Start EQ"].exists)
        // The same existing, entitlement-gated headphone browser remains accessible.
        app.buttons["Headphones"].click()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.click()
        app.typeText("AirPods Pro 3")
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Apple AirPods Pro 3")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testMenuRestoresHiddenAndMinimizedWindow() {
        let window = app.windows["Sonance EQ"]
        window.buttons[XCUIIdentifierMinimizeWindow].click()
        openFromMenuBar()
        XCTAssertTrue(window.buttons[XCUIIdentifierMinimizeWindow].waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons[XCUIIdentifierMinimizeWindow].isHittable)

        app.typeKey("h", modifierFlags: .command)
        openFromMenuBar()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(window.buttons[XCUIIdentifierCloseWindow].isHittable)
        XCTAssertEqual(app.windows.count, 1)
    }

    func testNativeWindowShortcutAndMenuQuit() {
        let window = app.windows["Sonance EQ"]
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        app.activate()
        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)

        menuBarItem.click()
        app.menuItems["Quit Sonance EQ"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testKeyboardMenuSelectionActivatesReopenedWindowFromFinder() {
        let window = app.windows["Sonance EQ"]
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))

        menuBarItem.click()
        XCTAssertTrue(app.menuItems["Open Sonance EQ"].waitForExistence(timeout: 5))
        finder.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Open Sonance EQ"].isSelected)
        finder.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(window.buttons[XCUIIdentifierCloseWindow].isHittable)
        XCTAssertEqual(app.windows.count, 1)
    }

    private var menuBarItem: XCUIElement {
        app.menuBars.menuBarItems["Sonance EQ"]
    }

    private func openFromMenuBar() {
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5))
        menuBarItem.click()
        let open = app.menuItems["Open Sonance EQ"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
