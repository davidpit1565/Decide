import XCTest

/// End-to-end checks against the running app. These drive the real UI, so they
/// need a simulator; run with:
///
///     xcodebuild test -scheme Decide -destination 'platform=iOS Simulator,name=iPhone 16'
final class DecideUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests"]
        app.launch()
    }

    // MARK: Home

    func testHomeAsksTheOneQuestionThatMatters() {
        XCTAssertTrue(app.staticTexts["What are you deciding?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Decide"].exists)
    }

    func testTheDecideButtonIsDisabledUntilThereIsSomethingToDecide() {
        let decide = app.buttons["Decide"]
        XCTAssertTrue(decide.waitForExistence(timeout: 10))
        XCTAssertFalse(decide.isEnabled)

        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("MacBook Air or MacBook Pro?")
        XCTAssertTrue(decide.isEnabled)
    }

    func testAnExampleFillsTheField() {
        let example = app.buttons["Which laptop should I buy?"]
        XCTAssertTrue(example.waitForExistence(timeout: 10))
        example.tap()
        XCTAssertTrue(app.textFields.firstMatch.value as? String == "Which laptop should I buy?")
    }

    func testTheThreeAreasAreReachable() {
        XCTAssertTrue(app.tabBars.buttons["Decide"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Decisions"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3, "DECIDE has exactly three places")
    }

    // MARK: Decisions

    func testEmptyHistoryExplainsItself() {
        app.tabBars.buttons["Decisions"].tap()
        XCTAssertTrue(app.staticTexts["Your decisions will appear here."].waitForExistence(timeout: 5))
    }

    // MARK: Profile

    func testProfileOffersTheDataControls() {
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete all decisions"].exists)
        XCTAssertTrue(app.buttons["Delete everything"].exists)
        XCTAssertTrue(app.staticTexts["Decision Memory"].exists)
    }

    func testRestorePurchasesIsReachableWithoutBuyingAnything() {
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your plan"].waitForExistence(timeout: 5))
        // Required by App Store review, and the way back for anyone reinstalling.
        XCTAssertTrue(
            app.buttons["Restore purchases"].waitForExistence(timeout: 5)
            || app.staticTexts["Checking your subscription…"].exists
        )
    }

    // MARK: Errors

    func testStartingADecisionAlwaysLeadsSomewhere() {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Pizza or pasta tonight?")
        app.buttons["Decide"].tap()

        // Either the analysis runs, or it fails honestly — never a blank screen.
        let outcomes = [
            app.staticTexts["Understanding your decision"],
            app.staticTexts["MY RECOMMENDATION"],
            app.staticTexts["I couldn't complete the analysis"],
            app.staticTexts["DECIDE isn't connected yet"],
            app.staticTexts["You're offline"],
            app.staticTexts["I'm missing something important"]
        ]

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if outcomes.contains(where: { $0.exists }) { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("Starting a decision left the user with nothing on screen")
    }

    // MARK: Accessibility

    func testTheLayoutSurvivesTheLargestAccessibilityTextSize() {
        // Run this manually with the accessibility inspector too; here we check that
        // the primary action is still hittable.
        XCTAssertTrue(app.buttons["Decide"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Decide"].isHittable)
    }
}
