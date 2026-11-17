import Foundation

/// Scripted watch motion (in the watch's own coordinate frame) for running the app in the
/// Simulator, which has no accelerometer or gyroscope. It plays the calibration poses and then
/// a loop of realistic sets with rests, so the full flow – calibration, live rep counting,
/// exercise detection, set summary – can be seen and UI-tested without a real watch.
enum MotionScript {
    enum Scenario {
        case calibration
        case workout
    }

    /// How the simulated watch is worn: left wrist, crown towards the hand (the default).
    static let wearing = CalibrationProfile.defaultProfile(wrist: .left, crownTowardsHand: true)

    static func samples(for scenario: Scenario, rate: Double = 50) -> [MotionSample] {
        switch scenario {
        case .calibration: return calibration(rate: rate)
        case .workout: return workout(rate: rate)
        }
    }

    // MARK: Calibration

    /// Physically consistent calibration with a 0.58 m arm (so the Simulator measures an arm
    /// length too), starting with the arm raised while the user reads the first instruction.
    static func calibration(rate: Double = 50) -> [MotionSample] {
        let reading = SyntheticCalibration.Pose(forearm: Vector3(0.3, 0.9, 0.3), palm: Vector3(0, 0, -1))
        return SyntheticCalibration.samples(armLength: 0.58, rate: rate, hold: 3.2, move: 1.0,
                                            lead: reading, leadSeconds: 2.5, overheadElevation: 85,
                                            wearing: wearing, noiseSeed: 1)
    }

    // MARK: Workout

    /// Sets played in a loop: (exercise, reps).
    static let workoutSets: [(ExerciseType, Int)] = [(.bicepCurl, 8), (.lateralRaise, 10), (.shoulderPress, 8)]

    static func workout(rate: Double = 50) -> [MotionSample] {
        var out: [MotionSample] = []
        var offset = 0.0
        for (i, entry) in workoutSets.enumerated() {
            var o = SyntheticMotion.Options()
            o.reps = entry.1
            o.stillLead = 4
            // A long first rest leaves time to review and save set 1 (UI test at 3× speed: ~30 s);
            // after that, the next set starting auto-saves an unreviewed summary.
            o.stillTail = i == 0 ? 90 : 40
            o.noise = 0.02
            o.sampleRate = rate
            o.seed = UInt64(10 + i)
            guard let arm = SyntheticMotion.generate(entry.0, options: o) else { continue }
            for s in arm {
                out.append(MotionSample(
                    timestamp: s.t + offset,
                    gravity: wearing.toDeviceFrame(s.gravity),
                    // CoreMotion convention: userAcceleration is the negative of the physical acceleration.
                    userAcceleration: wearing.toDeviceFrame(s.acceleration) * wearing.physicalAccelerationSign,
                    rotationRate: wearing.toDeviceFrame(s.rotation)
                ))
            }
            offset += (arm.last?.t ?? 0) + 1 / rate
        }
        return out
    }
}
