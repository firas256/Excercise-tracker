import Foundation

enum WristSide: String, Codable, Sendable {
    case left, right, unknown
}

/// Result of the guided calibration. Stores how the watch sits on the arm (the arm frame
/// expressed in watch coordinates) plus a few personal reference values.
struct CalibrationProfile: Codable, Equatable, Sendable {
    /// Unit vector (watch frame) pointing from elbow to hand.
    var forearmAxis: Vector3
    /// Unit vector (watch frame) pointing out of the palm.
    var palmAxis: Vector3
    var createdAt: Date
    var wrist: WristSide

    /// Highest forearm elevation reached in the overhead pose (degrees). Used to scale expectations
    /// for overhead exercises to the user's shoulder mobility.
    var overheadElevation: Double
    /// Lowest elevation (arms relaxed), usually close to -90.
    var restingElevation: Double
    /// How far the user could rotate from palm-down to palm-up (degrees, ideally ~180).
    var supinationRange: Double
    /// Sensor noise while standing still (rad/s); used to tune stillness thresholds.
    var stillnessNoise: Double
    /// Sign of the heading change when moving the arm from the front to the side (+1/-1, 0 = unknown).
    var abductionDirection: Double

    /// Third arm-frame axis, completing a right-handed frame.
    var radialAxis: Vector3 { forearmAxis.cross(palmAxis).normalized }

    var isFresh: Bool { Date().timeIntervalSince(createdAt) < 12 * 3600 }

    /// Fallback used before the first calibration: assumes the standard way of wearing an Apple Watch
    /// (watch x-axis along the forearm towards the hand, screen on the back of the wrist).
    static func defaultProfile(wrist: WristSide = .left, crownTowardsHand: Bool = true) -> CalibrationProfile {
        let forearm = crownTowardsHand ? Vector3.unitX : -Vector3.unitX
        return CalibrationProfile(
            forearmAxis: forearm,
            palmAxis: -Vector3.unitZ,
            createdAt: .distantPast,
            wrist: wrist,
            overheadElevation: 80,
            restingElevation: -88,
            supinationRange: 170,
            stillnessNoise: 0.03,
            abductionDirection: 0
        )
    }

    /// Expresses a watch-frame vector in the arm frame.
    func toArmFrame(_ v: Vector3) -> Vector3 {
        Vector3(v.dot(forearmAxis), v.dot(palmAxis), v.dot(radialAxis))
    }

    /// Inverse of `toArmFrame`: expresses an arm-frame vector in watch coordinates.
    func toDeviceFrame(_ v: Vector3) -> Vector3 {
        forearmAxis * v.x + palmAxis * v.y + radialAxis * v.z
    }

    func armSample(from s: MotionSample) -> ArmSample {
        ArmSample(
            t: s.timestamp,
            gravity: toArmFrame(s.gravity.normalized),
            acceleration: toArmFrame(s.userAcceleration),
            rotation: toArmFrame(s.rotationRate)
        )
    }
}
