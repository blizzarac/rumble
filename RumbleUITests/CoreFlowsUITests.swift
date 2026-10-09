import XCTest

/// The two core flows from the design doc: swipe → match → cook, and swipe → plan → list.
/// The app runs on fake services with an in-memory store when launched with `-ui-testing`.
@MainActor
final class CoreFlowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    /// Waits until the button exists and is enabled (the deck disables Yes / No while it is empty).
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let enabled = expectation(for: NSPredicate(format: "exists == true AND isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
    }

    func testSwipeToMatchToCook() {
        let app = launchApp()

        let yes = app.buttons["Yes"]
        waitForEnabled(yes)
        yes.tap()

        XCTAssertTrue(app.staticTexts["It's a match!"].waitForExistence(timeout: 5))
        app.buttons["Let's cook"].tap()

        // One step per page; walk to the last one.
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        let finish = app.buttons["Finish"]
        for _ in 0..<10 where !finish.exists {
            app.buttons["Next"].tap()
            _ = finish.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(finish.exists)
        finish.tap()

        // Back on the deck.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: finish)
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(app.buttons["Yes"].waitForExistence(timeout: 5))
    }

    func testSwipeToPlanToShoppingList() {
        let app = launchApp()

        app.buttons["Shop"].tap()
        XCTAssertTrue(app.staticTexts["Dinner 1 of 3"].waitForExistence(timeout: 5))

        let yes = app.buttons["Yes"]
        waitForEnabled(yes)
        yes.tap()
        XCTAssertTrue(app.staticTexts["Dinner 2 of 3"].waitForExistence(timeout: 5))
        yes.tap()
        XCTAssertTrue(app.staticTexts["Dinner 3 of 3"].waitForExistence(timeout: 5))
        yes.tap()

        let done = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Done shopping'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        // The plan resets and the deck is back.
        XCTAssertTrue(app.staticTexts["Dinner 1 of 3"].waitForExistence(timeout: 5))
    }
}
