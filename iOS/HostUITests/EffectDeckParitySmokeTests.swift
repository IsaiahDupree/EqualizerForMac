import XCTest

/// Interaction checks for the EffectDeck workflows inside the Sonance EQ host.
/// The routing case launches with a disposable seeded chain on the simulator.
final class EffectDeckParitySmokeTests: XCTestCase {
    @MainActor
    func testRoutingAndEffectBrowserOpenAndDismiss() {
        let app = XCUIApplication()
        app.launch()

        let effectsTab = app.tabBars.buttons["Effects"]
        XCTAssertTrue(effectsTab.waitForExistence(timeout: 20), "Effects tab is missing")
        effectsTab.tap()

        let moreMenu = app.buttons["moreMenu"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 10), "Effects toolbar is missing")
        moreMenu.tap()

        let routingAction = app.buttons["Routing"]
        XCTAssertTrue(routingAction.waitForExistence(timeout: 10), "Routing action is missing")
        routingAction.tap()

        XCTAssertTrue(app.navigationBars["Routing"].waitForExistence(timeout: 10),
                      "Routing screen did not open")
        XCTAssertTrue(app.staticTexts["Signal flow"].exists,
                      "Routing screen does not show the signal-flow list")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.exists, "Routing screen has no Done action")
        done.tap()

        let addEffect = app.buttons["Add Effect"]
        XCTAssertTrue(addEffect.waitForExistence(timeout: 10), "Add Effect action is missing")
        addEffect.tap()

        XCTAssertTrue(app.navigationBars["Available Effects"].waitForExistence(timeout: 10),
                      "Effect browser did not open")
        XCTAssertTrue(app.searchFields["Search effects"].exists,
                      "Effect browser search field is missing")

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "Effect browser has no Cancel action")
        cancel.tap()
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 10),
                      "Effect browser did not return to the chain")
    }

    @MainActor
    func testRoutingEditsChannelAndBusOnASeededChain() {
        let app = XCUIApplication()
        app.launchArguments = ["-ETSeed", "VolumePlugin,CompressorPlugin"]
        app.launch()

        let effectsTab = app.tabBars.buttons["Effects"]
        XCTAssertTrue(effectsTab.waitForExistence(timeout: 20), "Effects tab is missing")
        effectsTab.tap()

        let moreMenu = app.buttons["moreMenu"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 10), "Effects toolbar is missing")
        moreMenu.tap()
        let routingAction = app.buttons["Routing"]
        XCTAssertTrue(routingAction.waitForExistence(timeout: 10), "Routing action is missing")
        routingAction.tap()
        XCTAssertTrue(app.navigationBars["Routing"].waitForExistence(timeout: 10),
                      "Routing screen did not open")

        let outputBus = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Out")).firstMatch
        XCTAssertTrue(outputBus.waitForExistence(timeout: 10), "Output bus control is missing")
        outputBus.tap()
        let busOne = app.buttons["1"].firstMatch
        XCTAssertTrue(busOne.waitForExistence(timeout: 5), "Output bus choices did not open")
        busOne.tap()

        let channel = app.buttons["Channel"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 10), "Channel control is missing")
        channel.tap()
        let left = app.buttons["Left"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5), "Channel choices did not open")
        left.tap()

        app.navigationBars["Routing"].buttons["Done"].tap()
        let routeBadge = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "0→1 Left")).firstMatch
        XCTAssertTrue(routeBadge.waitForExistence(timeout: 10),
                      "The chain card did not reflect its changed bus and channel")

        moreMenu.tap()
        app.buttons["Routing"].tap()
        XCTAssertTrue(app.staticTexts["Left"].waitForExistence(timeout: 10),
                      "The routing screen did not restore the selected channel")
    }
}
