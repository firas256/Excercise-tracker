import XCTest
@testable import ExerciseCore

/// Feedback judged against the user's own calibrated body instead of an average person.
final class PersonalFeedbackTests: XCTestCase {

    private func rep(start: Double, peak: Double) -> RepMetrics {
        RepMetrics(index: 1, startTime: 0, duration: 3, concentricDuration: 1.2, eccentricDuration: 2,
                   rangeOfMotion: abs(peak - start), unit: .degrees, rangeFraction: 1, meanConcentricSpeed: 60,
                   peakSpeed: 120, startElevation: start, peakElevation: peak, issues: [], score: 100)
    }

    func testOverheadReachIsPersonal() {
        // Overhead triceps extension reaching 52°: short of an average reach (80°), but the full
        // reach for someone whose overhead pose measured 70°.
        let r = rep(start: 52, peak: -40)
        XCTAssertTrue(FeedbackEngine.positionIssues(r, exercise: .overheadTricepsExtension, body: .typical).contains(.incompleteTop))
        var stiff = BodyProfile.typical
        stiff.overheadElevation = 70
        XCTAssertFalse(FeedbackEngine.positionIssues(r, exercise: .overheadTricepsExtension, body: stiff).contains(.incompleteTop))
    }

    func testShoulderHeightIsPersonal() {
        // Lateral raise to -20°: short of shoulder height for most, but this watch reads -12° when
        // this user's arm is out at shoulder height.
        let r = rep(start: -85, peak: -20)
        var body = BodyProfile.typical
        body.sideElevation = 12
        XCTAssertTrue(FeedbackEngine.positionIssues(r, exercise: .lateralRaise, body: body).contains(.incompleteTop))
        body.sideElevation = -12
        XCTAssertFalse(FeedbackEngine.positionIssues(r, exercise: .lateralRaise, body: body).contains(.incompleteTop))
    }

    func testPushdownStartedFromTheBottomIsNotFlagged() {
        // Rep counted from the bottom (arm straight, -80°) up to the top (+15°).
        let r = rep(start: -80, peak: 15)
        XCTAssertFalse(FeedbackEngine.positionIssues(r, exercise: .tricepsPushdown).contains(.incompleteBottom))
        XCTAssertTrue(FeedbackEngine.positionIssues(rep(start: 15, peak: -40), exercise: .tricepsPushdown).contains(.incompleteBottom))
    }

    func testPressReachUsesArmLength() throws {
        func tips(amplitude: Double, armLength: Double?) throws -> [String] {
            var o = SyntheticMotion.Options()
            o.amplitudes = Array(repeating: amplitude, count: 8)
            let samples = try XCTUnwrap(SyntheticMotion.generate(.shoulderPress, options: o))
            var body = BodyProfile.typical
            body.measuredArmLength = armLength
            return SetAnalyzer(body: body).analyze(samples, lockedExercise: .shoulderPress).feedback.tips.map { $0.title }
        }
        XCTAssertFalse(try tips(amplitude: 1, armLength: 0.55).contains("Press all the way up"))
        XCTAssertTrue(try tips(amplitude: 0.35, armLength: 0.55).contains("Press all the way up"))
        // The same short press is a full press for a much shorter arm.
        XCTAssertFalse(try tips(amplitude: 0.35, armLength: 0.38).contains("Press all the way up"))
    }
}
