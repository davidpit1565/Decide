import XCTest

/// End-to-end checks against the running app.
///
/// These drive the real screens, the real pipeline and the real store. Only the
/// network call is scripted, via a DEBUG-only harness, so flows that would
/// otherwise need a deployed backend — a question round, a tie, a malformed
/// response — can be walked start to finish.
///
///     xcodebuild test -scheme Decide -destination 'platform=iOS Simulator,name=iPhone 16'
///
/// XCUIElement is main-actor isolated, so the whole case runs there.
@MainActor
final class DecideUITests: XCTestCase {

    private enum ID {
        static let startDecision = "decide.start"
        static let decisionInput = "decide.input"
        static let makeDecision = "decide.make"
        static let chooseSomethingElse = "decide.chooseOther"
        static let continueAfterQuestion = "decide.question.continue"
        static let doneWithDecision = "decide.done"
        static let tryAgain = "decide.retry"
    }

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() async throws {
        app = nil
    }

    // MARK: Launching

    /// - Parameters:
    ///   - scenario: which scripted exchange the app should serve.
    ///   - reset: clears the store first. Left off to test that data survives a relaunch.
    ///   - contentSize: a Dynamic Type category to launch under.
    private func launch(
        scenario: String? = nil,
        reset: Bool = true,
        contentSize: String? = nil
    ) {
        app.launchArguments = []
        if let scenario {
            app.launchArguments += ["-DecideUITestScenario", scenario]
        }
        if reset {
            app.launchArguments += ["-DecideUITestResetStore"]
        }
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
    }

    private func startDecision(_ text: String = "MacBook Air or MacBook Pro?") {
        let input = app.textFields[ID.decisionInput]
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The decision input should be the first thing on screen")
        input.tap()
        input.typeText(text)

        let decide = app.buttons[ID.startDecision]
        XCTAssertTrue(decide.isEnabled, "Decide should be enabled once there is something to decide")
        decide.tap()
    }

    // MARK: Home

    func testHomeAsksTheOneQuestionThatMatters() {
        launch()
        XCTAssertTrue(app.staticTexts["What are you deciding?"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons[ID.startDecision].exists)
    }

    func testTheDecideButtonIsDisabledUntilThereIsSomethingToDecide() {
        launch()
        let decide = app.buttons[ID.startDecision]
        XCTAssertTrue(decide.waitForExistence(timeout: 20))
        XCTAssertFalse(decide.isEnabled)

        let input = app.textFields[ID.decisionInput]
        input.tap()
        input.typeText("Which laptop?")
        XCTAssertTrue(decide.isEnabled)
    }

    func testAnExampleFillsTheField() {
        launch()
        let example = app.buttons["Which laptop should I buy?"]
        XCTAssertTrue(example.waitForExistence(timeout: 20))
        example.tap()
        XCTAssertEqual(app.textFields[ID.decisionInput].value as? String, "Which laptop should I buy?")
    }

    func testThereAreExactlyThreePlaces() {
        launch()
        XCTAssertTrue(app.tabBars.buttons["Decide"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.buttons["Decisions"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3, "No chat tab, no dashboard")
    }

    // MARK: The whole flow

    func testADecisionRunsFromHomeToHistory() {
        launch(scenario: "straightforward")
        startDecision()

        // Answer first: the recommendation, why, the trade-off, the strength.
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["MacBook Air"].exists)
        XCTAssertTrue(app.staticTexts["Why it fits you"].exists)
        XCTAssertTrue(app.staticTexts["Decision strength"].exists)
        XCTAssertTrue(app.staticTexts["Strong"].exists)
        XCTAssertTrue(app.staticTexts["What could make me wrong?"].exists)

        // Nothing was asked, because nothing needed asking.
        XCTAssertFalse(app.staticTexts["One thing I need to know"].exists)

        app.buttons[ID.makeDecision].tap()

        XCTAssertTrue(app.staticTexts["You chose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your choice is yours."].exists)

        app.buttons[ID.doneWithDecision].tap()

        // It is in history, with what was chosen and how strong it was.
        app.tabBars.buttons["Decisions"].tap()
        let row = app.staticTexts["MacBook Air vs MacBook Pro"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["MacBook Air · Strong"].exists)
    }

    func testTheAnalysisIsOneTapAwayAndShowsItsSources() {
        launch(scenario: "straightforward")
        startDecision()
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))

        app.buttons["See analysis"].tap()

        XCTAssertTrue(app.staticTexts["What you told me"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["What I judged it on"].exists)
        XCTAssertTrue(app.staticTexts["How the options compare"].exists)
        XCTAssertTrue(app.staticTexts["What I checked"].exists)
    }

    // MARK: Questions

    func testExactlyOneQuestionIsAskedAndNeverCounted() {
        launch(scenario: "oneQuestion")
        startDecision("Should I get the Air or the Pro for my work?")

        XCTAssertTrue(app.staticTexts["One thing I need to know"].waitForExistence(timeout: 30))

        // A direction is already on offer before the question is answered.
        XCTAssertTrue(app.staticTexts["I already have a direction"].exists)

        // No counter, anywhere.
        XCTAssertFalse(app.staticTexts["Question 1 of 5"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'question 1'")).count, 0)

        // Only the question the system cannot answer itself is shown.
        XCTAssertTrue(app.staticTexts["Do you edit video, or mostly photos and documents?"].exists)
        XCTAssertFalse(app.staticTexts["What do these cost today?"].exists)
        XCTAssertFalse(app.staticTexts["What colour do you prefer?"].exists)

        app.buttons["Mostly photos and documents"].tap()
        app.buttons[ID.continueAfterQuestion].tap()

        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
    }

    func testAQuestionCanBeDeclinedWithoutDeadEnding() {
        launch(scenario: "oneQuestion")
        startDecision()
        XCTAssertTrue(app.staticTexts["One thing I need to know"].waitForExistence(timeout: 30))

        app.buttons["I'd rather not say"].tap()
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
    }

    // MARK: Honest outcomes

    func testNoClearWinnerIsSaidRatherThanManufactured() {
        launch(scenario: "noClearWinner")
        startDecision()

        XCTAssertTrue(app.staticTexts["There isn't a clear winner"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Unclear"].exists)
        XCTAssertFalse(app.buttons[ID.makeDecision].exists, "There is nothing to recommend, so nothing to confirm")
        XCTAssertTrue(app.buttons["Choose for me anyway"].exists)
    }

    func testUnverifiedResearchIsDeclaredOnTheRecommendation() {
        launch(scenario: "researchFailure")
        startDecision()

        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] \"couldn't verify\"")
            ).firstMatch.exists,
            "A recommendation built on unverified research has to say so"
        )
    }

    func testAnInvalidResponseFailsHonestlyAndCanBeRetried() {
        launch(scenario: "invalidResponse")
        startDecision()

        XCTAssertTrue(app.staticTexts["I couldn't complete the analysis"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons[ID.tryAgain].exists)
        XCTAssertFalse(app.staticTexts["MY RECOMMENDATION"].exists, "A broken response must never render as an answer")
    }

    func testBeingOfflineIsExplainedNotFaked() {
        launch(scenario: "offline")
        startDecision()

        XCTAssertTrue(app.staticTexts["You're offline"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["MY RECOMMENDATION"].exists)
    }

    // MARK: The user's call

    func testOverridingTheRecommendationIsNotArguedWith() {
        launch(scenario: "straightforward")
        startDecision()
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))

        app.buttons[ID.chooseSomethingElse].tap()
        XCTAssertTrue(app.staticTexts["Your options"].waitForExistence(timeout: 10))
        app.staticTexts["MacBook Pro"].tap()

        XCTAssertTrue(app.staticTexts["You chose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["MacBook Pro"].exists)
        XCTAssertTrue(app.staticTexts["You're giving up"].exists)
        XCTAssertTrue(app.staticTexts["Your choice is yours."].exists)

        // No second-guessing anywhere on the screen.
        XCTAssertFalse(app.staticTexts["Are you sure?"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'accept'")).count, 0)
    }

    // MARK: Persistence and deletion

    func testADecisionSurvivesRelaunching() {
        launch(scenario: "straightforward")
        startDecision()
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
        app.buttons[ID.makeDecision].tap()
        XCTAssertTrue(app.buttons[ID.doneWithDecision].waitForExistence(timeout: 10))
        app.buttons[ID.doneWithDecision].tap()

        app.terminate()
        launch(scenario: "straightforward", reset: false)

        app.tabBars.buttons["Decisions"].tap()
        XCTAssertTrue(
            app.staticTexts["MacBook Air vs MacBook Pro"].waitForExistence(timeout: 20),
            "A saved decision must still be there after a restart"
        )
    }

    func testADecisionCanBeDeleted() {
        launch(scenario: "straightforward")
        startDecision()
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
        app.buttons[ID.makeDecision].tap()
        app.buttons[ID.doneWithDecision].tap()

        app.tabBars.buttons["Decisions"].tap()
        app.staticTexts["MacBook Air vs MacBook Pro"].tap()

        app.buttons["Delete this decision"].tap()
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["Your decisions will appear here."].waitForExistence(timeout: 10))
    }

    func testEverythingCanBeDeletedFromProfile() {
        launch(scenario: "straightforward")
        startDecision()
        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
        app.buttons[ID.makeDecision].tap()
        app.buttons[ID.doneWithDecision].tap()

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your data"].waitForExistence(timeout: 10))

        // Each kind of data can be deleted on its own.
        XCTAssertTrue(app.buttons["Delete all Decision Memory"].exists)
        XCTAssertTrue(app.buttons["Delete all outcomes"].exists)
        XCTAssertTrue(app.buttons["Delete all decisions"].exists)

        app.buttons["Delete everything"].tap()
        app.buttons["Delete"].tap()

        app.tabBars.buttons["Decisions"].tap()
        XCTAssertTrue(app.staticTexts["Your decisions will appear here."].waitForExistence(timeout: 10))
    }

    // MARK: Empty states and Pro

    func testEmptyHistoryExplainsItself() {
        launch()
        app.tabBars.buttons["Decisions"].tap()
        XCTAssertTrue(app.staticTexts["Your decisions will appear here."].waitForExistence(timeout: 20))
    }

    func testProfileOffersThePlanAndTheDataControls() {
        launch()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your plan"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Decision Memory"].exists)
        XCTAssertTrue(app.staticTexts["Your data"].exists)
    }

    func testThePaywallOnlyClaimsWhatProActuallyChanges() {
        launch()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your plan"].waitForExistence(timeout: 20))
        app.buttons["See Pro"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Make better decisions, with less effort."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Restore Purchases"].exists, "App Review requires this, and so does anyone reinstalling")

        // Claims the app cannot support must not be here.
        XCTAssertFalse(app.staticTexts["Advanced analysis"].exists)
        XCTAssertFalse(app.staticTexts["Stress testing"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'unlimited AI'")).count, 0)
    }

    // MARK: Accessibility and small screens

    func testTheFlowStillWorksAtTheLargestAccessibilityTextSize() {
        launch(scenario: "straightforward", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")

        let input = app.textFields[ID.decisionInput]
        XCTAssertTrue(input.waitForExistence(timeout: 20))

        let decide = app.buttons[ID.startDecision]
        XCTAssertTrue(decide.exists)
        XCTAssertTrue(decide.isHittable, "The primary action must stay reachable at the largest text size")

        input.tap()
        input.typeText("Air or Pro?")
        decide.tap()

        XCTAssertTrue(app.staticTexts["MY RECOMMENDATION"].waitForExistence(timeout: 30))
        let makeDecision = app.buttons[ID.makeDecision]
        XCTAssertTrue(makeDecision.exists)
        XCTAssertTrue(makeDecision.isHittable, "The decision must still be makeable at the largest text size")
    }

    func testTheKeyboardDoesNotCoverThePrimaryAction() {
        launch()
        let input = app.textFields[ID.decisionInput]
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        input.tap()
        input.typeText("Which laptop should I buy?")

        let decide = app.buttons[ID.startDecision]
        XCTAssertTrue(decide.isHittable, "The CTA has to stay above the keyboard")
    }
}
