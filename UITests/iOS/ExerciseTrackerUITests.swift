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

    /// Swipes to the next page until `text` shows (a swipe on a busy Simulator sometimes doesn't turn the page).
    private func swipe(_ app: XCUIApplication, untilShowing text: String) -> Bool {
        for _ in 0..<3 {
            if app.staticTexts[text].exists { return true }
            app.swipeLeft()
            if app.staticTexts[text].waitForExistence(timeout: 6) { return true }
        }
        return false
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

        XCTAssertTrue(swipe(app, untilShowing: "How it works"))
        snap(app, "ios-02-how-it-works")

        XCTAssertTrue(swipe(app, untilShowing: "Permissions"))
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

    // MARK: Accessibility

    /// Apple's accessibility audit (contrast, VoiceOver labels, tap-target size, Dynamic Type,
    /// clipped text…) on every main screen. Every issue is listed with its screen and element.
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoWorkout", "YES"]
        app.launch()
        var issues: [String] = []
        func audit(_ screen: String) throws {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id '\($0.identifier)'" } ?? "?"
                issues.append("\(screen) | \(Self.name(issue.auditType)) | \(issue.compactDescription) | \(element)")
                return true  // collect them all; asserted below
            }
        }

        XCTAssertTrue(app.staticTexts["Last 7 days"].waitForExistence(timeout: 20))
        try audit("Today")
        openTab(app, "History")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        try audit("History")
        app.cells.firstMatch.tap()
        let curl = app.staticTexts["Bicep Curl"].firstMatch
        XCTAssertTrue(curl.waitForExistence(timeout: 5))
        try audit("Workout")
        curl.tap()
        XCTAssertTrue(app.staticTexts["Feedback"].waitForExistence(timeout: 5))
        try audit("Set")
        openTab(app, "Exercises")
        XCTAssertTrue(app.staticTexts["Bicep Curl"].firstMatch.waitForExistence(timeout: 5))
        try audit("Exercises")
        openTab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try audit("Settings")
        let about = app.buttons["Privacy, safety & credits"]
        for _ in 0..<6 where !(about.exists && about.isHittable) { app.swipeUp() }
        about.tap()
        XCTAssertTrue(app.staticTexts["Your privacy"].waitForExistence(timeout: 5) || app.staticTexts["YOUR PRIVACY"].exists)
        snap(app, "ios-42-privacy")
        try audit("About")
        app.terminate()

        app.launchArguments = ["-onboardingComplete", "YES", "-demoLiveWorkout", "live"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Live workout"].waitForExistence(timeout: 15))
        try audit("Live workout")
        app.terminate()

        app.launchArguments = ["-onboardingComplete", "YES", "-demoCalibration", "YES", "-guideSpeechMuted", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Arm forward"].waitForExistence(timeout: 15))
        try audit("Calibration guide")

        let report = XCTAttachment(string: issues.joined(separator: "\n"))
        report.name = "accessibility-issues"
        report.lifetime = .keepAlways
        add(report)
        print("ACCESSIBILITY ISSUES (\(issues.count)):\n" + issues.joined(separator: "\n"))
        XCTAssert(issues.isEmpty, "\(issues.count) accessibility issues:\n" + issues.joined(separator: "\n"))
    }

    private static func name(_ type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
            (.sufficientElementDescription, "description"), (.dynamicType, "dynamic type"),
            (.textClipped, "text clipped"), (.trait, "trait"),
        ]
        let found = names.filter { type.contains($0.0) }.map { $0.1 }
        return found.isEmpty ? "other(\(type.rawValue))" : found.joined(separator: "+")
    }
}
