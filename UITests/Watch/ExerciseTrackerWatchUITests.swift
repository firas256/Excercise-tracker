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

    func testHomeScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-watchOnboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Start Workout"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Calibrate"].exists)
        snap(app, "watch-01-home")
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
        // Started the way the iPhone starts it (no tap on the watch: a system interruption on a slow
        // Simulator could invalidate the button mid-tap). The home screen has its own test.
        app.launchArguments = ["-watchOnboarded", "YES", "-calibrateEveryWorkout", "YES", "-simulationSpeed", "3",
                               "-speakInstructions", "NO", "-skipHealthPrompt", "YES", "-startWorkoutFromPhone", "YES"]
        app.launch()

        // Guided calibration (scripted motion plays in real time): each pose is detected automatically.
        // On a slow Simulator a pose can be over before a screenshot of the previous one is done,
        // so follow along by polling and photograph whichever step is showing; reaching the
        // tracking screen is what proves calibration finished.
        // (The first step is polled too: on a slow Simulator it can be over before the first look.)
        let steps = [("Arms down", "watch-02-calibration-arms-down"), ("Arm forward", "watch-03-calibration-arm-forward"),
                     ("Palm up", "watch-03b-calibration-palm-up"), ("Arm to the side", "watch-03c-calibration-arm-side"),
                     ("Arm overhead", "watch-04-calibration-overhead"), ("Calibrated!", "watch-05-calibrated")]
        var seen: [String] = []
        let tracking = app.staticTexts["reps"], trackingOne = app.staticTexts["rep"]
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline, !(tracking.exists || trackingOne.exists) {
            for (title, shot) in steps where !seen.contains(title) && app.staticTexts[title].exists {
                seen.append(title)
                snap(app, shot)
            }
        }
        XCTAssertTrue(tracking.exists || trackingOne.exists, "calibration never finished (steps seen: \(seen))")
        // Which steps got photographed depends on the Simulator's speed (after a tap, XCTest waits for
        // the app to settle, and a calibrating watch never quite does), so it's reported, not asserted.
        print("Calibration steps photographed: \(seen)")

        // Live tracking of the first scripted set (8 bicep curls).
        snap(app, "watch-06-waiting-for-set")
        let guess = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Curl'")).firstMatch
        XCTAssertTrue(guess.waitForExistence(timeout: 40), "exercise guess never appeared")
        snap(app, "watch-07-live-reps")

        // Set summary after the rest period (the script rests ~40 s before the next set; if the next
        // set starts before Save is tapped, the app saves the summary by itself, which is fine too).
        let save = app.buttons["Save Set"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "set summary never appeared")
        snap(app, "watch-08-set-summary")
        app.swipeUp()
        snap(app, "watch-09-set-summary-feedback")
        if save.exists { scrollUntilHittable(save, in: app) }
        XCTAssertEqual(app.state, .runningForeground, "app state: \(app.state.rawValue)")
        snap(app, "watch-10-set-summary-bottom")
        if save.exists && save.isHittable { save.tap() }

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
