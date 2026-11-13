import Foundation

/// One raw device-motion reading from the watch (CoreMotion sensor fusion output), in the
/// watch's own coordinate frame. Units: gravity & userAcceleration in g, rotationRate in rad/s.
struct MotionSample: Codable, Equatable, Sendable {
    var timestamp: Double
    var gravity: Vector3
    var userAcceleration: Vector3
    var rotationRate: Vector3
    var attitude: Quaternion

    init(timestamp: Double, gravity: Vector3, userAcceleration: Vector3, rotationRate: Vector3, attitude: Quaternion = .identity) {
        self.timestamp = timestamp
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.attitude = attitude
    }
}

/// A motion sample expressed in the user's *arm frame* (learned during calibration), so that the
/// exact way the watch is worn (left/right wrist, crown left/right) no longer matters.
///
/// Arm-frame axes:
///  - forearm: from elbow towards the hand
///  - palm:    out of the palm (pointing down when the palm faces the floor)
///  - radial:  completes the right-handed frame (forearm x palm)
struct ArmSample: Codable, Equatable, Sendable {
    /// Seconds (monotonic).
    var t: Double
    /// Unit gravity direction in arm frame (x: forearm, y: palm, z: radial).
    var gravity: Vector3
    /// User acceleration (gravity removed) in arm frame, in g.
    var acceleration: Vector3
    /// Angular velocity in arm frame, rad/s.
    var rotation: Vector3

    /// Forearm elevation in degrees: -90 = pointing at the floor, 0 = horizontal, +90 = pointing up.
    var elevation: Double {
        asin(SignalMath.clamp(-gravity.x, -1, 1)) * 180 / .pi
    }

    /// Vertical (world "up") component of the user acceleration, in m/s².
    var verticalAcceleration: Double {
        -acceleration.dot(gravity) * 9.80665
    }

    /// Acceleration along the forearm axis in m/s² (positive = towards the fingers).
    var forearmAcceleration: Double { acceleration.x * 9.80665 }

    /// Angular velocity about world vertical (up), rad/s.
    var yawRate: Double { -rotation.dot(gravity) }

    /// Forearm roll angle (degrees) — only meaningful when the forearm is not vertical.
    /// 0 = palm facing the floor, ±180 = palm facing up, ±90 = thumb up/down (neutral grip).
    var roll: Double {
        atan2(gravity.z, gravity.y) * 180 / .pi
    }

    /// 0...1 weight describing how horizontal the forearm is (1 = horizontal, 0 = vertical).
    var horizontality: Double { max(0, 1 - gravity.x * gravity.x) }

    /// Rough motion energy used for activity detection (rad/s + g, unitless blend).
    var motionEnergy: Double { rotation.length + 2 * acceleration.length }
}

/// How the hand holds the weight, seen as the forearm's roll with the forearm roughly horizontal.
enum Grip: String, Codable, CaseIterable, Sendable {
    /// Palm facing the floor (overhand), e.g. bar pushdown, lateral raise. Watch face up.
    case pronated
    /// Thumb up, palm facing in, e.g. hammer curl, rope pushdown. Watch face to the side.
    case neutral
    /// Palm facing up (underhand), e.g. bicep curl. Watch face down.
    case supinated

    /// Roll away from palm-down (degrees) for a typical (full) range of forearm rotation.
    var nominalRoll: Double {
        switch self {
        case .pronated: return 0
        case .neutral: return 90
        case .supinated: return 180
        }
    }
}
