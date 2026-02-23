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
        advanceThroughSlides()
        tapStartDemoAndReturn()
        relaunchAndExpectCTA()
    }

    private func assertSplashThenOnboarding() {
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
    }

    private func advanceThroughSlides() {
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
        app.launchArguments = ["-uiTesting", "-returningUser"]
        app.launch()
        let startDemo = app.buttons["Start Free Demo"]
        XCTAssertTrue(startDemo.waitForExistence(timeout: 2))
    }
}
