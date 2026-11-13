import XCTest

/// Walks through every iPhone screen and attaches a screenshot of each.
/// Run with ⌘U on an iPhone simulator (scheme "ExerciseTracker").
final class ExerciseTrackerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 3) {
            tabButton.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
    }

    func testOnboardingFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Rep Coach"].waitForExistence(timeout: 15))
        snap(app, "ios-01-welcome")

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["How it works"].waitForExistence(timeout: 5))
        snap(app, "ios-02-how-it-works")

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Permissions"].waitForExistence(timeout: 5))
        snap(app, "ios-03-permissions")

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10) || app.buttons["Today"].exists)
        snap(app, "ios-04-after-onboarding")
    }

    func testCalibrationGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoCalibration", "YES", "-guideSpeechMuted", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Arm forward"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Calibrating on Apple Watch"].exists)
        snap(app, "ios-50-calibration-guide")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Calibrating on Apple Watch"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start workout on Apple Watch"].waitForExistence(timeout: 5))
        snap(app, "ios-51-dashboard-start-on-watch")
    }

    func testDemoWorkoutScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoWorkout", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Last 7 days"].waitForExistence(timeout: 20))
        snap(app, "ios-10-dashboard")
        app.swipeUp()
        snap(app, "ios-11-dashboard-scrolled")

        openTab(app, "History")
        let firstWorkout = app.cells.firstMatch
        XCTAssertTrue(firstWorkout.waitForExistence(timeout: 5))
        snap(app, "ios-20-history")
        firstWorkout.tap()

        let curl = app.staticTexts["Bicep Curl"].firstMatch
        XCTAssertTrue(curl.waitForExistence(timeout: 5))
        snap(app, "ios-21-workout-detail")
        curl.tap()

        XCTAssertTrue(app.staticTexts["Feedback"].waitForExistence(timeout: 5))
        snap(app, "ios-22-set-detail")
        app.swipeUp()
        snap(app, "ios-23-set-charts")
        app.swipeUp()
        snap(app, "ios-24-set-speed")
        app.swipeUp()
        snap(app, "ios-25-set-reps")

        openTab(app, "Exercises")
        let curlRow = app.staticTexts["Bicep Curl"].firstMatch
        XCTAssertTrue(curlRow.waitForExistence(timeout: 5))
        snap(app, "ios-30-exercise-library")
        curlRow.tap()
        XCTAssertTrue(app.staticTexts["Form cue"].waitForExistence(timeout: 5))
        snap(app, "ios-31-exercise-detail")

        openTab(app, "Settings")
        let howItWorks = app.buttons["How Rep Coach works"]
        XCTAssertTrue(howItWorks.waitForExistence(timeout: 5))
        snap(app, "ios-40-settings")
        howItWorks.tap()
        XCTAssertTrue(app.staticTexts["Calibration"].waitForExistence(timeout: 5))
        snap(app, "ios-41-how-it-works")
    }
}
