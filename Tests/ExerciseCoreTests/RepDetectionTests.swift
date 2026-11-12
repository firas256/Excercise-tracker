import XCTest
@testable import ExerciseCore

final class RepDetectionTests: XCTestCase {

    static let simulated: [ExerciseType] = [
        .bicepCurl, .hammerCurl, .lateralRaise, .frontRaise, .shoulderPress, .benchPress, .gobletSquat,
        .deadlift, .seatedCableRow, .chestPressMachine, .tricepsPushdown, .latPulldown, .pecDeck,
    ]

    func testCountsRepsForEverySimulatedExercise() throws {
        for exercise in Self.simulated {
            for reps in [5, 10] {
                var o = SyntheticMotion.Options()
                o.reps = reps
                let samples = try XCTUnwrap(SyntheticMotion.generate(exercise, options: o))
                let analysis = SetAnalyzer().analyze(samples)
                XCTAssertEqual(analysis.repCount, reps, "\(exercise) expected \(reps) reps, got \(analysis.repCount) (signal \(String(describing: analysis.detection?.signal)))")
            }
        }
    }

    func testCountsRepsWithKnownExerciseAndVaryingTempo() throws {
        for exercise in Self.simulated {
            for (con, ecc) in [(0.7, 1.0), (1.5, 3.0)] {
                var o = SyntheticMotion.Options()
                o.reps = 6
                o.concentric = con
                o.eccentric = ecc
                o.seed = 11
                let samples = try XCTUnwrap(SyntheticMotion.generate(exercise, options: o))
                let analysis = SetAnalyzer().analyze(samples, lockedExercise: exercise)
                XCTAssertEqual(analysis.repCount, 6, "\(exercise) tempo \(con)/\(ecc): got \(analysis.repCount)")
            }
        }
    }

    func testRangeOfMotionIsMeasured() throws {
        let curl = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl))
        let a = SetAnalyzer().analyze(curl, lockedExercise: .bicepCurl)
        XCTAssertEqual(a.detection?.signal, .elevation)
        XCTAssertEqual(a.feedback.averageRange, 120, accuracy: 8)
        XCTAssertEqual(a.reps.first?.startElevation ?? 0, -80, accuracy: 6)
        XCTAssertEqual(a.reps.first?.peakElevation ?? 0, 40, accuracy: 6)

        let press = try XCTUnwrap(SyntheticMotion.generate(.shoulderPress))
        let p = SetAnalyzer().analyze(press, lockedExercise: .shoulderPress)
        XCTAssertEqual(p.detection?.signal, .vertical)
        XCTAssertEqual(p.feedback.averageRange, 42, accuracy: 6)
    }

    func testTempoPhasesAreMeasured() throws {
        var o = SyntheticMotion.Options()
        o.concentric = 1.0
        o.eccentric = 2.5
        let curl = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl, options: o))
        let a = SetAnalyzer().analyze(curl, lockedExercise: .bicepCurl)
        XCTAssertEqual(a.feedback.averageConcentric, 1.0, accuracy: 0.3)
        XCTAssertEqual(a.feedback.averageEccentric, 2.5, accuracy: 0.5)

        // Squat goes down first: the lowering must be labelled eccentric.
        let squat = try XCTUnwrap(SyntheticMotion.generate(.gobletSquat, options: o))
        let s = SetAnalyzer().analyze(squat, lockedExercise: .gobletSquat)
        XCTAssertEqual(s.detection?.restHigh, true)
        XCTAssertEqual(s.feedback.averageConcentric, 1.0, accuracy: 0.3)
        XCTAssertEqual(s.feedback.averageEccentric, 2.5, accuracy: 0.5)
    }

    func testPartialRepsAreFlagged() throws {
        var o = SyntheticMotion.Options()
        o.reps = 8
        o.amplitudes = [1, 1, 1, 1, 1, 0.6, 1, 0.55]
        let samples = try XCTUnwrap(SyntheticMotion.generate(.lateralRaise, options: o))
        let a = SetAnalyzer().analyze(samples, lockedExercise: .lateralRaise)
        XCTAssertEqual(a.repCount, 8)
        let partial = a.reps.filter { $0.issues.contains(.partialRange) }.map { $0.index }
        XCTAssertEqual(partial, [6, 8])
        XCTAssertTrue(a.feedback.tips.contains { $0.title == "Use your full range" })
    }

    func testRushedLoweringIsFlagged() throws {
        var o = SyntheticMotion.Options()
        o.concentric = 1.0
        o.eccentric = 0.45
        o.pauseBottom = 0.6
        let samples = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl, options: o))
        let a = SetAnalyzer().analyze(samples, lockedExercise: .bicepCurl)
        XCTAssertGreaterThanOrEqual(a.repCount, 7)
        XCTAssertTrue(a.reps.allSatisfy { $0.issues.contains(.rushedLowering) })
        XCTAssertTrue(a.feedback.tips.contains { $0.title == "Slow the lowering" })
    }

    func testCleanSetScoresHigh() throws {
        let samples = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl))
        let a = SetAnalyzer().analyze(samples, lockedExercise: .bicepCurl)
        XCTAssertGreaterThanOrEqual(a.feedback.score, 90)
        XCTAssertTrue(a.feedback.tips.contains { $0.kind == .positive })
    }

    func testStillnessProducesNoReps() {
        var rng = SeededRandom(seed: 5)
        let samples = (0..<500).map { i in
            ArmSample(t: Double(i) / 50,
                      gravity: Vector3(1, 0.01 * rng.gaussian(), 0.01 * rng.gaussian()).normalized,
                      acceleration: Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.01,
                      rotation: Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.02)
        }
        XCTAssertEqual(SetAnalyzer().analyze(samples).repCount, 0)
    }
}
