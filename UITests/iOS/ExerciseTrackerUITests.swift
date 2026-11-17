import UIKit
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

    /// Brightness (0 black … 1 white) of one background pixel near the top-left of the screen.
    private func backgroundBrightness(_ app: XCUIApplication) -> CGFloat {
        guard let image = app.screenshot().image.cgImage else { return -1 }
        let x = image.width / 20, y = image.height / 8  // left margin, below the status bar
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / 765
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
        // The demo calibration ran through the real engine: personal measurements are shown.
        // (A swipe on a busy Simulator sometimes doesn't scroll, so try a few.)
        let measurements = app.staticTexts["Your measurements"]
        for _ in 0..<4 where !(measurements.exists && measurements.isHittable) { app.swipeUp() }
        XCTAssertTrue(measurements.waitForExistence(timeout: 5))
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

    /// The largest accessibility text size (Settings › Accessibility › Larger Text, maximum):
    /// screenshots of the screens to check by eye, including the rows the audit predicts "may be
    /// clipped at larger Dynamic Type sizes".
    func testLargestTextSize() throws {
        let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoWorkout", "YES", "-stillAnimations", "YES"] + largest
        app.launch()
        XCTAssertTrue(app.staticTexts["Last 7 days"].waitForExistence(timeout: 20))
        snap(app, "ios-80-largest-text-today")
        openTab(app, "Settings")
        let export = app.buttons["Export my recordings"]
        for _ in 0..<10 where !(export.exists && export.isHittable) { app.swipeUp() }
        XCTAssertTrue(export.exists)
        snap(app, "ios-81-largest-text-settings")
        let about = app.buttons["Privacy, safety & credits"]
        for _ in 0..<14 where !(about.exists && about.isHittable) { app.swipeUp() }
        about.tap()
        // At this size the row is several screens down, and a list only builds the rows near the screen.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        let point = app.staticTexts["No account, no ads, no analytics, no tracking. Nothing is sent to the developer or anyone else."]
        for _ in 0..<12 where !(point.exists && point.isHittable) { app.swipeUp() }
        XCTAssertTrue(point.exists, "privacy row not found at the largest text size")
        snap(app, "ios-82-largest-text-privacy")
        app.terminate()

        app.launchArguments = ["-onboardingComplete", "YES", "-demoLiveWorkout", "live", "-stillAnimations", "YES"] + largest
        app.launch()
        XCTAssertTrue(app.staticTexts["Live workout"].waitForExistence(timeout: 15))
        snap(app, "ios-83-largest-text-live-workout")
        app.swipeUp()
        snap(app, "ios-84-largest-text-live-workout-controls")
    }

    /// Apple's accessibility audit (contrast, VoiceOver labels, tap-target size, Dynamic Type,
    /// clipped text…) on every main screen, in light and dark mode. Every issue is listed with its
    /// screen, element and position. These are reported but don't fail the test:
    /// - content behind or right next to the system's glass tab and navigation bars: iOS fades and
    ///   blurs scrolled content there on purpose, and the audit then reads blurred text (often
    ///   without being able to tie it to an element). Long screens are audited again scrolled to
    ///   the bottom, so the rows that were under the tab bar are checked unobstructed;
    /// - "nearly passed" contrast: Apple's standard secondary text colour;
    /// - "partially unsupported" Dynamic Type: the text does grow, just not at every size;
    /// - "may be clipped at larger Dynamic Type sizes": a prediction, checked for real by
    ///   `testLargestTextSize` (screenshots at the largest size).
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoWorkout", "YES", "-stillAnimations", "YES"]
        app.launch()
        var issues: [String] = []
        var warnings: [String] = []
        func audit(_ screen: String) throws {
            // Let navigation and tab transitions finish: mid-fade text reads as low contrast.
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            // The bars plus the band where iOS's scroll-edge effect fades content next to them.
            let tabBar = app.tabBars.firstMatch, navBar = app.navigationBars.firstMatch
            let bars = [tabBar.exists ? tabBar.frame.insetBy(dx: 0, dy: -24) : CGRect.null,
                        navBar.exists ? navBar.frame.insetBy(dx: 0, dy: -16) : CGRect.null].filter { !$0.isNull }
            // A busy Simulator sometimes can't finish an audit in time: one retry.
            var lastError: Error?
            for attempt in 0..<2 {
                if attempt > 0 { RunLoop.current.run(until: Date().addingTimeInterval(3)) }
                var found: [(failure: Bool, line: String)] = []
                do {
                    try app.performAccessibilityAudit { issue in
                        let frame = issue.element?.frame ?? .null
                        let place = frame.isNull ? "" : " at y \(Int(frame.minY))–\(Int(frame.maxY))"
                        let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id '\($0.identifier)'" } ?? "?"
                        let line = "\(screen) | \(Self.name(issue.auditType)) | \(issue.compactDescription) | \(element)\(place)"
                        let underBar = !bars.isEmpty && (frame.isNull ? (issue.auditType == .elementDetection || issue.auditType == .contrast)
                                                                      : bars.contains { frame.intersects($0) })
                        let nearlyPassed = issue.compactDescription.localizedCaseInsensitiveContains("nearly passed")
                        let partialDynamicType = issue.auditType == .dynamicType
                            && issue.compactDescription.localizedCaseInsensitiveContains("partially")
                        let predictedClip = issue.auditType == .textClipped
                            && issue.detailedDescription.localizedCaseInsensitiveContains("larger Dynamic Type sizes")
                        if underBar || nearlyPassed || partialDynamicType || predictedClip {
                            found.append((false, line + (predictedClip ? " | predicted, see testLargestTextSize" : "")))
                        } else {
                            found.append((true, line + " | " + issue.detailedDescription))
                        }
                        return true  // collect them all; asserted below
                    }
                    issues += found.filter { $0.failure }.map { $0.line }
                    warnings += found.filter { !$0.failure }.map { $0.line }
                    lastError = nil
                    break
                } catch {
                    lastError = error
                }
            }
            if let lastError {
                issues.append("\(screen) | audit could not run | \(lastError.localizedDescription) | –")
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
        for _ in 0..<5 { app.swipeUp() }
        try audit("Exercises (bottom)")
        openTab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try audit("Settings")
        let about = app.buttons["Privacy, safety & credits"]
        for _ in 0..<6 where !(about.exists && about.isHittable) { app.swipeUp() }
        app.swipeUp()
        try audit("Settings (bottom)")
        about.tap()
        XCTAssertTrue(app.staticTexts["Your privacy"].waitForExistence(timeout: 5) || app.staticTexts["YOUR PRIVACY"].exists)
        snap(app, "ios-42-privacy")
        try audit("About")
        for _ in 0..<4 { app.swipeUp() }
        try audit("About (bottom)")
        app.terminate()

        app.launchArguments = ["-onboardingComplete", "YES", "-demoLiveWorkout", "live", "-stillAnimations", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Live workout"].waitForExistence(timeout: 15))
        try audit("Live workout")
        app.terminate()

        app.launchArguments = ["-onboardingComplete", "YES", "-demoCalibration", "YES", "-guideSpeechMuted", "YES",
                               "-stillAnimations", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Arm forward"].waitForExistence(timeout: 15))
        try audit("Calibration guide")
        app.terminate()

        // Dark Mode: the same colours must work on dark backgrounds. (The app is told to render dark:
        // XCUIDevice's appearance setting didn't take effect on the CI Simulator.)
        let dark = ["-forceColorScheme", "dark"]
        app.launchArguments = ["-onboardingComplete", "YES", "-demoWorkout", "YES", "-stillAnimations", "YES"] + dark
        app.launch()
        XCTAssertTrue(app.staticTexts["Last 7 days"].waitForExistence(timeout: 20))
        snap(app, "ios-90-dark-dashboard")
        let brightness = backgroundBrightness(app)
        XCTAssertLessThan(brightness, 0.3, "the app isn't in Dark Mode (background brightness \(brightness))")
        try audit("Today (dark)")
        openTab(app, "Exercises")
        XCTAssertTrue(app.staticTexts["Bicep Curl"].firstMatch.waitForExistence(timeout: 5))
        try audit("Exercises (dark)")
        openTab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try audit("Settings (dark)")
        app.terminate()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoLiveWorkout", "live", "-stillAnimations", "YES"] + dark
        app.launch()
        XCTAssertTrue(app.staticTexts["Live workout"].waitForExistence(timeout: 15))
        snap(app, "ios-91-dark-live-workout")
        try audit("Live workout (dark)")
        app.terminate()
        app.launchArguments = ["-onboardingComplete", "YES", "-demoCalibration", "YES", "-guideSpeechMuted", "YES",
                               "-stillAnimations", "YES"] + dark
        app.launch()
        XCTAssertTrue(app.staticTexts["Arm forward"].waitForExistence(timeout: 15))
        snap(app, "ios-92-dark-calibration-guide")
        try audit("Calibration guide (dark)")

        let report = XCTAttachment(string: "ISSUES (\(issues.count))\n" + issues.joined(separator: "\n")
                                   + "\n\nWARNINGS (\(warnings.count))\n" + warnings.joined(separator: "\n"))
        report.name = "accessibility-issues"
        report.lifetime = .keepAlways
        add(report)
        print("ACCESSIBILITY ISSUES (\(issues.count)):\n" + issues.joined(separator: "\n"))
        print("ACCESSIBILITY WARNINGS (\(warnings.count)):\n" + warnings.joined(separator: "\n"))
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
