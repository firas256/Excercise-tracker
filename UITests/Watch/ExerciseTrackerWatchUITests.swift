import XCTest

/// End-to-end watch flow in the Simulator using scripted motion (see `MotionScript`):
/// home → guided calibration → live rep counting → set summary → save → end workout.
/// Run with ⌘U on an Apple Watch simulator (scheme "ExerciseTracker Watch App").
final class ExerciseTrackerWatchUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while element.exists && !element.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
    }

    func testOnboardingScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-watchOnboarded", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Allow Access"].waitForExistence(timeout: 20))
        snap(app, "watch-00-onboarding")
    }

    func testCalibrationAndWorkoutWithSimulatedMotion() {
        let app = XCUIApplication()
        app.launchArguments = ["-watchOnboarded", "YES", "-calibrateEveryWorkout", "YES", "-simulationSpeed", "3"]
        app.launch()

        let start = app.buttons["Start Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        snap(app, "watch-01-home")
        start.tap()

        // Guided calibration (scripted motion plays in real time): each pose is detected automatically.
        XCTAssertTrue(app.staticTexts["Arms down"].waitForExistence(timeout: 15))
        snap(app, "watch-02-calibration-arms-down")
        XCTAssertTrue(app.staticTexts["Arm forward"].waitForExistence(timeout: 20))
        snap(app, "watch-03-calibration-arm-forward")
        XCTAssertTrue(app.staticTexts["Arm overhead"].waitForExistence(timeout: 30))
        snap(app, "watch-04-calibration-overhead")
        XCTAssertTrue(app.staticTexts["Calibrated!"].waitForExistence(timeout: 20))
        snap(app, "watch-05-calibrated")

        // Live tracking of the first scripted set (8 bicep curls).
        XCTAssertTrue(app.staticTexts["reps"].waitForExistence(timeout: 20) || app.staticTexts["rep"].exists)
        snap(app, "watch-06-waiting-for-set")
        let guess = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Curl'")).firstMatch
        XCTAssertTrue(guess.waitForExistence(timeout: 40), "exercise guess never appeared")
        snap(app, "watch-07-live-reps")

        // Set summary after the rest period (the script rests ~25 s before the next set).
        let save = app.buttons["Save Set"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "set summary never appeared")
        snap(app, "watch-08-set-summary")
        app.swipeUp()
        snap(app, "watch-09-set-summary-feedback")
        scrollUntilHittable(save, in: app)
        XCTAssertEqual(app.state, .runningForeground, "app state: \(app.state.rawValue)")
        snap(app, "watch-10-set-summary-bottom")
        save.tap()

        XCTAssertTrue(app.staticTexts["Set 2"].waitForExistence(timeout: 10))
        snap(app, "watch-11-rest")
        // The next scripted set (lateral raises) starts on its own.
        let nextGuess = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Raise'")).firstMatch
        XCTAssertTrue(nextGuess.waitForExistence(timeout: 60), "second set was not detected")
        snap(app, "watch-12-second-set")

        // Controls page → end the workout.
        app.swipeRight()
        let end = app.buttons["End Workout"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        snap(app, "watch-13-controls")
        scrollUntilHittable(end, in: app)
        end.tap()
        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 10))
        // The set that was still in progress when the workout ended must be kept.
        XCTAssertTrue(app.staticTexts["Bicep Curl"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Raise'")).firstMatch.exists,
                      "in-progress set was dropped when ending the workout")
        snap(app, "watch-14-summary")
    }
}
