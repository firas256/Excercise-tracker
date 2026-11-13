import XCTest

/// Walks through every iPhone screen and attaches a screenshot of each.
/// Run with ⌘U on an iPhone simulator (scheme "ExerciseTracker").
final class ExerciseTrackerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Don't leave an animating demo running in the Simulator (it slows down the Watch tests that run next).
    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
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

    func testLiveWorkoutOnPhone() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoLiveWorkout", "live"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Live workout"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Good rep"].exists)
        sleep(2)  // let the arm animation run
        snap(app, "ios-60-live-workout")

        // Lock the exercise from the phone.
        app.buttons["Choose exercise"].tap()
        XCTAssertTrue(app.navigationBars["Exercise"].waitForExistence(timeout: 5))
        // Only rows of the picker list (the live screen's chips are still behind the sheet).
        let hammer = app.collectionViews.staticTexts["Hammer Curl"].firstMatch
        XCTAssertTrue(hammer.waitForExistence(timeout: 5))
        snap(app, "ios-61-choose-exercise")
        hammer.tap()
        XCTAssertTrue(app.buttons["Back to auto-detect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hammer Curl"].exists)
        XCTAssertFalse(app.staticTexts["Bicep Curl"].exists)
        snap(app, "ios-62-exercise-locked")

        // Tuck the workout away and bring it back from the dashboard.
        app.buttons["Minimize"].tap()
        let banner = app.buttons["liveWorkoutBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        snap(app, "ios-63-dashboard-banner")
        banner.tap()
        XCTAssertTrue(app.staticTexts["Live workout"].waitForExistence(timeout: 5))

        // End the workout from the phone.
        app.swipeUp()
        app.buttons["End workout"].tap()
        let confirm = app.buttons["End Workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Live workout"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Start workout on Apple Watch"].waitForExistence(timeout: 5))
    }

    func testSetReviewOnPhone() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoLiveWorkout", "review"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Set done"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Save set"].exists)
        snap(app, "ios-65-set-review")
        app.buttons["Save set"].tap()
        XCTAssertTrue(app.navigationBars["Set done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rest"].waitForExistence(timeout: 5))
        snap(app, "ios-66-resting")
    }

    func testDemoWorkoutScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoWorkout", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Last 7 days"].waitForExistence(timeout: 20))
        snap(app, "ios-10-dashboard")
        app.swipeUp()
        // The demo calibration ran through the real engine: personal measurements are shown.
        XCTAssertTrue(app.staticTexts["Your measurements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Arm (shoulder to watch)"].exists)
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
        let replay = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Arm motion replay'")).firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        sleep(2)  // let the replay play a little
        snap(app, "ios-26-set-replay")
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snap(app, "ios-40-settings")
        // The demo's sensor recordings add a training-data section, so the link sits further down.
        let howItWorks = app.buttons["How Rep Coach works"]
        for _ in 0..<6 where !(howItWorks.exists && howItWorks.isHittable) { app.swipeUp() }
        XCTAssertTrue(howItWorks.waitForExistence(timeout: 5))
        howItWorks.tap()
        XCTAssertTrue(app.staticTexts["Calibration"].waitForExistence(timeout: 5))
        snap(app, "ios-41-how-it-works")
    }
}
