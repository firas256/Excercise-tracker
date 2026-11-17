import XCTest
@testable import ExerciseCore

/// Reps covering less than half the required range – the larger of the user's full range for the
/// exercise (from calibration) and their best reps in the set – are not counted.
final class ShortRepTests: XCTestCase {

    private func analyze(_ exercise: ExerciseType, amplitudes: [Double], locked: Bool = false,
                         body: BodyProfile = .typical) throws -> SetAnalysis {
        var o = SyntheticMotion.Options()
        o.reps = amplitudes.count
        o.amplitudes = amplitudes
        let samples = try XCTUnwrap(SyntheticMotion.generate(exercise, options: o))
        return SetAnalyzer(body: body).analyze(samples, lockedExercise: locked ? exercise : nil)
    }

    func testShortRepsInASetAreNotCounted() throws {
        // 8 curls, two of them only ~40 % of the way up.
        let a = try analyze(.bicepCurl, amplitudes: [1, 1, 0.4, 1, 1, 0.4, 1, 1])
        XCTAssertEqual(a.repCount, 6)
        XCTAssertEqual(a.tooShortReps.count, 2)
        XCTAssertEqual(a.reps.map { $0.index }, Array(1...6))
        XCTAssertTrue(a.feedback.tips.contains { $0.title == "2 reps not counted" }, "\(a.feedback.tips.map { $0.title })")
    }

    func testPartialButNotTooShortRepsStillCount() throws {
        // 60–70 % of the range: counted, but flagged as partial.
        let a = try analyze(.bicepCurl, amplitudes: [1, 1, 1, 0.65, 1, 0.6, 1, 1])
        XCTAssertEqual(a.repCount, 8)
        XCTAssertTrue(a.tooShortReps.isEmpty)
        XCTAssertTrue(a.reps.contains { $0.issues.contains(.partialRange) })
    }

    func testAWholeSetOfHalfRepsIsJudgedAgainstTheFullRange() throws {
        // Every curl only goes ~40 % of the way: compared with the set itself they'd all look fine,
        // but against a full curl (from calibration) none counts.
        let a = try analyze(.bicepCurl, amplitudes: Array(repeating: 0.4, count: 8), locked: true)
        XCTAssertEqual(a.repCount, 0)
        XCTAssertEqual(a.tooShortReps.count, 8)
    }

    func testQuarterSquatsAreNotCounted() throws {
        // The synthetic goblet squat drops the hands 50 cm; 20 % of that (10 cm) is well under half
        // of a parallel squat for an average adult (~34 cm).
        let a = try analyze(.gobletSquat, amplitudes: Array(repeating: 0.2, count: 6), locked: true)
        XCTAssertEqual(a.repCount, 0)
        XCTAssertEqual(a.requiredRange ?? 0, BodyProfile.typical.parallelSquatTravel * 100, accuracy: 0.5)
        // Full squats count.
        XCTAssertEqual(try analyze(.gobletSquat, amplitudes: Array(repeating: 1, count: 6), locked: true).repCount, 6)
    }

    func testSquatDepthIsJudgedForTheUsersHeight() {
        // 15 cm squats: under half a parallel squat for an average adult (~34 cm), over half for a
        // small person (arm 0.40 m ≈ 1.28 m tall: parallel ≈ 26 cm).
        let reps = (1...6).map { i in
            RepMetrics(index: i, startTime: Double(i) * 3, duration: 3, concentricDuration: 1, eccentricDuration: 2,
                       rangeOfMotion: 15, unit: .centimeters, rangeFraction: 1, meanConcentricSpeed: 15, peakSpeed: 30,
                       startElevation: 70, peakElevation: 70, issues: [], score: 100)
        }
        var small = BodyProfile.typical
        small.measuredArmLength = 0.40
        func counted(_ body: BodyProfile) -> Int {
            FeedbackEngine.separateTooShort(reps, exercise: .gobletSquat, exerciseIsCertain: true,
                                            signal: .vertical, body: body).counted.count
        }
        XCTAssertEqual(counted(.typical), 0)
        XCTAssertEqual(counted(small), 6)
    }

    func testUncertainGuessDoesNotDiscardReps() throws {
        // Without a locked or confident exercise, only the set's own best reps set the bar.
        let reps = (1...6).map { i in
            RepMetrics(index: i, startTime: Double(i) * 3, duration: 3, concentricDuration: 1, eccentricDuration: 2,
                       rangeOfMotion: 50, unit: .degrees, rangeFraction: 1, meanConcentricSpeed: 50, peakSpeed: 80,
                       startElevation: -80, peakElevation: -30, issues: [], score: 100)
        }
        let unsure = FeedbackEngine.separateTooShort(reps, exercise: .bicepCurl, exerciseIsCertain: false,
                                                     signal: .elevation, body: .typical)
        XCTAssertEqual(unsure.counted.count, 6)
        let sure = FeedbackEngine.separateTooShort(reps, exercise: .bicepCurl, exerciseIsCertain: true,
                                                   signal: .elevation, body: .typical)
        XCTAssertEqual(sure.counted.count, 0)
    }

    func testFullRepsAreNeverRejected() throws {
        var problems: [String] = []
        for exercise in RepDetectionTests.simulated {
            for seed: UInt64 in [1, 2, 3] {
                var o = SyntheticMotion.Options()
                o.seed = seed
                let samples = try XCTUnwrap(SyntheticMotion.generate(exercise, options: o))
                for locked in [false, true] {
                    let a = SetAnalyzer().analyze(samples, lockedExercise: locked ? exercise : nil)
                    // (Whether every rep is found at all is RepDetectionTests' business; here: the
                    // too-short rule must never remove or flag a full rep.)
                    if !a.tooShortReps.isEmpty || a.repCount != a.detection?.segments.count {
                        problems.append("\(exercise.rawValue) seed \(seed) locked \(locked): counted \(a.repCount), not counted \(a.tooShortReps.map { Int($0.rangeOfMotion) })")
                    }
                }
            }
        }
        XCTAssert(problems.isEmpty, "\n" + problems.joined(separator: "\n"))
    }

    func testLiveTrackerSaysWhenARepDidNotCount() throws {
        var o = SyntheticMotion.Options()
        o.reps = 6
        o.amplitudes = [1, 1, 1, 0.4, 1, 1]
        let samples = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl, options: o))
        let tracker = LiveSetTracker()
        tracker.lockedExercise = .bicepCurl
        var notCounted = 0
        var final: SetAnalysis?
        for s in samples {
            for e in tracker.ingest(s) {
                if case .repNotCounted = e { notCounted += 1 }
                if case .setCompleted(let set) = e { final = set.analysis }
            }
        }
        for e in tracker.finishSet() { if case .setCompleted(let set) = e { final = set.analysis } }
        XCTAssertEqual(notCounted, 1)
        XCTAssertEqual(final?.repCount, 5)
    }
}
