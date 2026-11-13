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

    private struct ArmPose {
        var forearm: Vector3
        var palm: Vector3
    }

    /// Arm pose in the world (x forward, y left, z up) → device-frame sample.
    private static func sample(_ pose: ArmPose, t: Double, rotation: Vector3 = .zero, noise: inout SeededRandom) -> MotionSample {
        let f = wearing.forearmAxis, p = wearing.palmAxis, r = wearing.radialAxis
        let fw = pose.forearm.normalized
        let pw = pose.palm.orthogonalized(against: fw).normalized
        let rw = fw.cross(pw)
        func world(_ d: Vector3) -> Vector3 { fw * d.dot(f) + pw * d.dot(p) + rw * d.dot(r) }
        let q = Quaternion(rotationColumns: world(.unitX), world(.unitY), world(.unitZ))
        let tremor = Vector3(noise.gaussian(), noise.gaussian(), noise.gaussian())
        return MotionSample(
            timestamp: t,
            gravity: q.conjugate.rotate(Vector3(0, 0, -1)),
            userAcceleration: tremor * 0.005,
            rotationRate: rotation + tremor * 0.02,
            attitude: q
        )
    }

    static func calibration(rate: Double = 50) -> [MotionSample] {
        let reading = ArmPose(forearm: Vector3(0.3, 0.9, 0.3), palm: Vector3(0, 0, -1))
        let poses: [ArmPose] = [
            ArmPose(forearm: Vector3(0, 0, -1), palm: Vector3(0, 1, 0)),   // arms down, palm to thigh
            ArmPose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, -1)),   // forward, palm down
            ArmPose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, 1)),    // forward, palm up
            ArmPose(forearm: Vector3(0, 1, 0), palm: Vector3(0, 0, -1)),   // side, palm down
            ArmPose(forearm: Vector3(0, 0, 1), palm: Vector3(-1, 0, 0)),   // overhead
        ]
        var out: [MotionSample] = []
        var noise = SeededRandom(seed: 1)
        var t = 0.0
        let dt = 1 / rate
        func hold(_ pose: ArmPose, seconds: Double) {
            for _ in 0..<Int(seconds * rate) { out.append(sample(pose, t: t, noise: &noise)); t += dt }
        }
        func move(to pose: ArmPose, seconds: Double) {
            for _ in 0..<Int(seconds * rate) {
                out.append(sample(pose, t: t, rotation: Vector3(0.4, 1.6, 0.2), noise: &noise))
                t += dt
            }
        }
        hold(reading, seconds: 2.5)          // user reads the first instruction
        for pose in poses {
            move(to: pose, seconds: 0.8)
            hold(pose, seconds: 3.2)
        }
        move(to: poses[0], seconds: 0.8)
        hold(poses[0], seconds: 5)
        return out
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
            o.stillTail = 25
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
