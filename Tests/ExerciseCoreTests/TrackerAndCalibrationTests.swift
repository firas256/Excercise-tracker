import XCTest
@testable import ExerciseCore

final class LiveSetTrackerTests: XCTestCase {

    func testStreamingCurlSet() throws {
        var o = SyntheticMotion.Options()
        o.reps = 8
        o.stillLead = 3
        o.stillTail = 7
        o.noise = 0.03
        let samples = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl, options: o))
        let tracker = LiveSetTracker()
        var started = 0
        var counts: [Int] = []
        var guesses: [ExerciseType] = []
        var completed: CompletedSet?
        for s in samples {
            for e in tracker.ingest(s) {
                switch e {
                case .setStarted: started += 1
                case .repsUpdated(let c, _): counts.append(c)
                case .repNotCounted(let rep): XCTFail("full rep not counted: \(rep)")
                case .exerciseGuess(let c): guesses.append(c[0].exercise)
                case .setCompleted(let set): completed = set
                case .setDiscarded(let reason): XCTFail("discarded: \(reason)")
                }
            }
        }
        XCTAssertEqual(started, 1)
        XCTAssertEqual(counts.last, 8)
        XCTAssertEqual(counts, counts.sorted(), "rep count should only go up: \(counts)")
        XCTAssertEqual(guesses.last, .bicepCurl)
        let set = try XCTUnwrap(completed)
        XCTAssertEqual(set.analysis.repCount, 8)
        XCTAssertEqual(set.analysis.exercise, .bicepCurl)
        XCTAssertFalse(tracker.isActive)
    }

    func testManualFinishAndLockedExercise() throws {
        var o = SyntheticMotion.Options()
        o.reps = 5
        o.stillTail = 0.5
        let samples = try XCTUnwrap(SyntheticMotion.generate(.shoulderPress, options: o))
        let tracker = LiveSetTracker()
        tracker.lockedExercise = .shoulderPress
        var guessed = false
        for s in samples {
            for e in tracker.ingest(s) { if case .exerciseGuess = e { guessed = true } }
        }
        XCTAssertFalse(guessed, "locked exercise must not be re-guessed")
        let events = tracker.finishSet()
        guard case .setCompleted(let set)? = events.first else { return XCTFail("expected completion, got \(events)") }
        XCTAssertEqual(set.analysis.repCount, 5)
        XCTAssertEqual(set.analysis.exercise, .shoulderPress)
    }

    func testSmallFidgetIsDiscarded() {
        // A single short arm movement must not be logged as a set.
        var samples: [ArmSample] = []
        for i in 0..<600 {
            let t = Double(i) / 50
            let moving = t > 2 && t < 2.8
            let w = moving ? 2.0 : 0.01
            samples.append(ArmSample(t: t, gravity: Vector3(1, 0, 0), acceleration: Vector3(0.01, 0, 0), rotation: Vector3(0, 0, w)))
        }
        let tracker = LiveSetTracker()
        var discarded = false, completed = false
        for s in samples {
            for e in tracker.ingest(s) {
                if case .setDiscarded = e { discarded = true }
                if case .setCompleted = e { completed = true }
            }
        }
        XCTAssertTrue(discarded)
        XCTAssertFalse(completed)
    }
}

final class CalibrationEngineTests: XCTestCase {

    /// Simulates the watch for a given true wear orientation and arm pose (arm axes in world).
    private func sample(t: Double, forearmDev f: Vector3, palmDev p: Vector3,
                        forearmWorld fw: Vector3, palmWorld pw: Vector3, rotation: Vector3 = .zero) -> MotionSample {
        let r = f.cross(p).normalized
        let rw = fw.cross(pw).normalized
        func world(_ d: Vector3) -> Vector3 { fw * d.dot(f) + pw * d.dot(p) + rw * d.dot(r) }
        let q = Quaternion(rotationColumns: world(.unitX), world(.unitY), world(.unitZ))
        let gravity = q.conjugate.rotate(Vector3(0, 0, -1))
        return MotionSample(timestamp: t, gravity: gravity, userAcceleration: .zero, rotationRate: rotation, attitude: q)
    }

    private struct ArmPose { var forearm: Vector3; var palm: Vector3 }

    private func runCalibration(forearmDev f: Vector3, palmDev p: Vector3, poses override: [Int: ArmPose] = [:]) -> [CalibrationEvent] {
        let poses: [ArmPose] = [
            ArmPose(forearm: Vector3(0, 0, -1), palm: Vector3(0, 1, 0)),   // arm down, palm facing thigh
            ArmPose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, -1)),   // forward, palm down
            ArmPose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, 1)),    // forward, palm up
            ArmPose(forearm: Vector3(0, -1, 0), palm: Vector3(0, 0, -1)),  // side, palm down
            ArmPose(forearm: Vector3(0, 0, 1), palm: Vector3(-1, 0, 0)),   // overhead
        ]
        let engine = CalibrationEngine(wrist: .left, crownTowardsHand: true)
        var events = engine.start()
        var t = 0.0
        for (i, basePose) in poses.enumerated() {
            let pose = override[i] ?? basePose
            if i > 0 {
                for _ in 0..<40 {  // 0.8 s of movement
                    events += engine.ingest(sample(t: t, forearmDev: f, palmDev: p, forearmWorld: pose.forearm, palmWorld: pose.palm, rotation: Vector3(0, 1.5, 0)))
                    t += 0.02
                }
            }
            for _ in 0..<120 {  // 2.4 s still
                events += engine.ingest(sample(t: t, forearmDev: f, palmDev: p, forearmWorld: pose.forearm, palmWorld: pose.palm))
                t += 0.02
            }
        }
        return events
    }

    private func finishedProfile(_ events: [CalibrationEvent]) -> CalibrationProfile? {
        for e in events { if case .finished(let p) = e { return p } }
        return nil
    }

    func testLearnsArmFrameForDifferentWearingStyles() throws {
        let tilt = Quaternion(axis: Vector3(0.3, 1, 0.2), angle: 0.25)
        let setups: [(Vector3, Vector3)] = [
            (Vector3(1, 0, 0), Vector3(0, 0, -1)),          // left wrist, crown towards hand
            (Vector3(-1, 0, 0), Vector3(0, 0, -1)),         // crown towards elbow
            (tilt.rotate(Vector3(1, 0, 0)), tilt.rotate(Vector3(0, 0, -1))), // loose / tilted strap
        ]
        for (f, p) in setups {
            let events = runCalibration(forearmDev: f, palmDev: p)
            XCTAssertFalse(events.contains { if case .wrongPose = $0 { return true } else { return false } }, "\(events)")
            let profile = try XCTUnwrap(finishedProfile(events), "\(events)")
            XCTAssertGreaterThan(profile.forearmAxis.dot(f), 0.99)
            XCTAssertGreaterThan(profile.palmAxis.dot(p), 0.99)
            XCTAssertEqual(profile.overheadElevation, 90, accuracy: 3)
            XCTAssertEqual(profile.supinationRange, 180, accuracy: 3)
            XCTAssertNotEqual(profile.abductionDirection, 0)

            // A device-frame sample of a curl pose maps back to the right elevation.
            let s = sample(t: 0, forearmDev: f, palmDev: p, forearmWorld: Vector3(cos(0.5), 0, sin(0.5)), palmWorld: Vector3(-sin(0.5), 0, cos(0.5)))
            XCTAssertEqual(profile.armSample(from: s).elevation, 0.5 * 180 / .pi, accuracy: 1)
        }
    }

    func testFirstPoseWaitsQuietlyWhileUserReadsTheScreen() {
        let f = Vector3(1, 0, 0), p = Vector3(0, 0, -1)
        let engine = CalibrationEngine()
        var events = engine.start()
        var t = 0.0
        // Arm raised, looking at the watch, perfectly still for 4 s: no complaint, no capture.
        for _ in 0..<200 {
            events += engine.ingest(sample(t: t, forearmDev: f, palmDev: p, forearmWorld: Vector3(0.3, 0.9, 0.3).normalized, palmWorld: Vector3(0, 0, -1)))
            t += 0.02
        }
        XCTAssertFalse(events.contains { if case .wrongPose = $0 { return true }; if case .poseCaptured = $0 { return true }; return false }, "\(events)")
        // Lower the arm and hold: captured.
        for _ in 0..<40 {
            events += engine.ingest(sample(t: t, forearmDev: f, palmDev: p, forearmWorld: Vector3(0, 0, -1), palmWorld: Vector3(0, 1, 0), rotation: Vector3(0, 2, 0)))
            t += 0.02
        }
        for _ in 0..<120 {
            events += engine.ingest(sample(t: t, forearmDev: f, palmDev: p, forearmWorld: Vector3(0, 0, -1), palmWorld: Vector3(0, 1, 0)))
            t += 0.02
        }
        XCTAssertTrue(events.contains(.poseCaptured(.armsDown)), "\(events)")
    }

    func testWrongPoseIsReported() {
        // Arm only half raised in the "forward" step.
        let half = ArmPose(forearm: Vector3(0.7, 0, -0.7).normalized, palm: Vector3(-0.7, 0, -0.7).normalized)
        let events = runCalibration(forearmDev: Vector3(1, 0, 0), palmDev: Vector3(0, 0, -1), poses: [1: half])
        XCTAssertTrue(events.contains(.wrongPose("Raise your arm to shoulder height")), "\(events)")
    }
}

final class CodingTests: XCTestCase {
    func testWorkoutRoundTrip() throws {
        let samples = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl))
        let a = SetAnalyzer().analyze(samples)
        let set = SetRecord(id: UUID(), exercise: .bicepCurl, detectedExercise: a.exercise, detectionConfidence: a.confidence,
                            alternatives: Array(a.candidates.prefix(3)), userCorrectedExercise: false, repCount: a.repCount,
                            detectedRepCount: a.repCount, reps: a.reps, feedback: a.feedback, signal: .elevation, weight: 12.5,
                            weightUnit: "kg", startDate: Date(), endDate: Date(), features: a.features)
        let w = WorkoutRecord(id: UUID(), startDate: Date(), endDate: Date(), sets: [set], averageHeartRate: 110,
                              activeEnergyKilocalories: 80, calibratedAt: Date())
        let data = try XCTUnwrap(PayloadCoding.encode(w))
        let back = try XCTUnwrap(PayloadCoding.decode(WorkoutRecord.self, from: data))
        XCTAssertEqual(back.sets.first?.repCount, a.repCount)
        XCTAssertEqual(back.sets.first?.reps.count, a.reps.count)

        var personalization = ClassifierPersonalization()
        personalization.add(try XCTUnwrap(a.features), label: .bicepCurl)
        let pd = try JSONEncoder().encode(personalization)
        XCTAssertEqual(try JSONDecoder().decode(ClassifierPersonalization.self, from: pd), personalization)
    }

    func testTrainingCSVRoundTrip() throws {
        let samples = try XCTUnwrap(SyntheticMotion.generate(.hammerCurl))
        let csv = TrainingCSV.make(samples)
        XCTAssertTrue(csv.hasPrefix(TrainingCSV.columns.joined(separator: ",")))
        let parsed = TrainingCSV.parse(csv)
        XCTAssertEqual(parsed.count, samples.count)
        XCTAssertEqual(parsed[100].rotation.y, samples[100].rotation.y, accuracy: 1e-3)
    }
}

final class CalibrationLiveStateTests: XCTestCase {
    func testMapsPhasesAndThrottles() throws {
        let holding = CalibrationLiveState(step: 1, pose: .armForward, phase: .holding(0.3))
        XCTAssertEqual(holding.status, .holding)
        XCTAssertEqual(holding.progress, 0.3, accuracy: 1e-9)
        let wrong = CalibrationLiveState(step: 1, pose: .armForward, phase: .wrongPose("Raise your arm to shoulder height"))
        XCTAssertEqual(wrong.status, .wrongPose)
        XCTAssertEqual(wrong.message, "Raise your arm to shoulder height")
        // Small progress changes are not resent; quarter steps and status changes are.
        let slightlyMore = CalibrationLiveState(step: 1, pose: .armForward, phase: .holding(0.4))
        XCTAssertFalse(CalibrationLiveState.isWorthSending(slightlyMore, after: holding))
        XCTAssertTrue(CalibrationLiveState.isWorthSending(CalibrationLiveState(step: 1, pose: .armForward, phase: .holding(0.55)), after: holding))
        XCTAssertTrue(CalibrationLiveState.isWorthSending(wrong, after: holding))
        // Round-trips through the WatchConnectivity payload encoding.
        let data = try XCTUnwrap(PayloadCoding.encode(wrong))
        XCTAssertEqual(PayloadCoding.decode(CalibrationLiveState.self, from: data), wrong)
    }
}
