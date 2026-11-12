import XCTest
@testable import ExerciseCore

/// The simulator script must drive the real calibration and tracking pipeline end to end.
final class MotionScriptTests: XCTestCase {

    func testCalibrationScriptCompletesCalibration() throws {
        let engine = CalibrationEngine(wrist: .left, crownTowardsHand: true)
        var events = engine.start()
        for s in MotionScript.samples(for: .calibration) { events += engine.ingest(s) }
        let wrongPoses = events.filter { if case .wrongPose = $0 { return true } else { return false } }
        XCTAssertTrue(wrongPoses.isEmpty, "\(wrongPoses)")
        var profile: CalibrationProfile?
        for e in events { if case .finished(let p) = e { profile = p } }
        let p = try XCTUnwrap(profile, "calibration did not finish: \(events)")
        XCTAssertGreaterThan(p.forearmAxis.dot(MotionScript.wearing.forearmAxis), 0.99)
        XCTAssertGreaterThan(p.palmAxis.dot(MotionScript.wearing.palmAxis), 0.99)
        XCTAssertEqual(p.overheadElevation, 90, accuracy: 3)
    }

    func testWorkoutScriptProducesExpectedSets() {
        let tracker = LiveSetTracker()
        let profile = MotionScript.wearing
        var completed: [CompletedSet] = []
        for s in MotionScript.samples(for: .workout) {
            for e in tracker.ingest(profile.armSample(from: s)) {
                if case .setCompleted(let set) = e { completed.append(set) }
            }
        }
        XCTAssertEqual(completed.map { $0.analysis.repCount }, MotionScript.workoutSets.map { $0.1 })
        XCTAssertEqual(completed.first?.analysis.exercise, .bicepCurl)
        print("Simulated workout guesses:", completed.map { "\($0.analysis.exercise?.rawValue ?? "?") \($0.analysis.repCount)" })
    }
}
