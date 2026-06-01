import XCTest

final class GirlPowerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetOnboarding"]
        app.launch()
    }

    func testFirstRunFlowThenBypassOnRelaunch() {
        assertSplashThenOnboarding()
        assertProgressAndCompletionGuard()
        advanceThroughSlidesAndComplete()
        tapStartDemoAndReturn()
        relaunchAndExpectCTA()
    }

    private func assertSplashThenOnboarding() {
        let splashScreen = app.otherElements["splash_screen"]
        XCTAssertTrue(splashScreen.waitForExistence(timeout: 1))

        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Start Free Demo"].exists)
    }

    private func assertProgressAndCompletionGuard() {
        let progressLabel = app.staticTexts["onboarding_progress_label"]
        XCTAssertTrue(progressLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(progressLabel.label, "1/3")
        XCTAssertFalse(app.buttons["Continue"].exists)

        app.swipeLeft()
        XCTAssertTrue(waitForProgressLabel("2/3"))
        XCTAssertFalse(app.buttons["Continue"].exists)

        app.swipeLeft()
        XCTAssertTrue(waitForProgressLabel("3/3"))
        XCTAssertTrue(app.buttons["Continue"].exists)

        app.swipeRight()
        XCTAssertTrue(waitForProgressLabel("2/3"))
        app.swipeRight()
        XCTAssertTrue(waitForProgressLabel("1/3"))
        XCTAssertFalse(app.buttons["Continue"].exists)
    }

    private func advanceThroughSlidesAndComplete() {
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 2))
        nextButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 2))
        nextButton.tap()
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 2))
        continueButton.tap()
    }

    private func tapStartDemoAndReturn() {
        let startDemo = app.buttons["Start Free Demo"]
        XCTAssertTrue(startDemo.waitForExistence(timeout: 2))
        startDemo.tap()
        let backButton = app.buttons["demo_toolbar_back_button"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()
    }

    private func relaunchAndExpectCTA() {
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let startDemo = app.buttons["Start Free Demo"]
        XCTAssertTrue(startDemo.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Next"].exists)
        XCTAssertFalse(app.buttons["Continue"].exists)
    }

    private func waitForProgressLabel(_ value: String, timeout: TimeInterval = 2) -> Bool {
        let predicate = NSPredicate(format: "label == %@", value)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: app.staticTexts["onboarding_progress_label"]
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
