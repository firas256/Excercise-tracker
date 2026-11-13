import Foundation

/// The user's own body as measured during calibration, so tracking and feedback fit *them* rather
/// than an average person:
///  - the angles their arm actually shows in each pose (their "shoulder height" and "overhead"),
///  - how far their forearm turns from palm-down to palm-up,
///  - their arm length, from how far the watch rises between "arms down" and "arm forward" (a
///    straight arm swinging up by 90° lifts the wrist by exactly one arm length).
/// Forearm, upper arm, height and shoulder height are then estimated from standard body
/// proportions (Drillis & Contini): upper arm 0.186 H, forearm 0.146 H, shoulder height 0.818 H.
struct BodyProfile: Codable, Equatable, Sendable {
    /// Forearm angle (deg) with the straight arm forward at shoulder height (≈ 0).
    var forwardElevation: Double
    /// Forearm angle (deg) with the straight arm out to the side at shoulder height (≈ 0).
    var sideElevation: Double
    /// Forearm angle (deg) reaching straight overhead: 70–90 depending on shoulder mobility.
    var overheadElevation: Double
    /// How far the forearm turns from palm-down to palm-up (deg, typically 150–180).
    var supinationRange: Double
    /// Shoulder → watch distance with the arm straight (m), measured during calibration.
    var measuredArmLength: Double?

    /// Shoulder → watch for an average adult (1.72 m).
    static let typicalArmLength = 0.546
    /// The watch sits about 2.5 cm above the wrist joint.
    static let watchOffset = 0.025

    static let typical = BodyProfile(forwardElevation: 0, sideElevation: 0, overheadElevation: 80,
                                     supinationRange: 170, measuredArmLength: nil)

    init(forwardElevation: Double, sideElevation: Double, overheadElevation: Double,
         supinationRange: Double, measuredArmLength: Double?) {
        self.forwardElevation = SignalMath.clamp(forwardElevation, -30, 30)
        self.sideElevation = SignalMath.clamp(sideElevation, -30, 30)
        self.overheadElevation = SignalMath.clamp(overheadElevation, 50, 95)
        self.supinationRange = SignalMath.clamp(supinationRange, 100, 190)
        self.measuredArmLength = measuredArmLength
    }

    init(profile: CalibrationProfile) {
        self.init(forwardElevation: profile.forwardElevation ?? 0,
                  sideElevation: profile.sideElevation ?? 0,
                  overheadElevation: profile.overheadElevation,
                  supinationRange: profile.supinationRange,
                  measuredArmLength: profile.armLength)
    }

    /// Shoulder → watch (m), measured or typical.
    var armLength: Double { measuredArmLength ?? Self.typicalArmLength }
    var isArmLengthMeasured: Bool { measuredArmLength != nil }
    /// Estimated standing height (m).
    var estimatedHeight: Double { (armLength + Self.watchOffset) / 0.332 }
    /// Elbow → watch (m): the radius the watch swings on when only the forearm moves.
    var forearmLength: Double { 0.146 * estimatedHeight - Self.watchOffset }
    /// Shoulder → elbow (m).
    var upperArmLength: Double { 0.186 * estimatedHeight }
    /// Shoulder height above the floor (m).
    var shoulderHeight: Double { 0.818 * estimatedHeight }
    /// Size relative to the average person the built-in movement patterns describe (0.75–1.25).
    var sizeScale: Double { SignalMath.clamp(armLength / Self.typicalArmLength, 0.75, 1.25) }

    /// How far the wrist should rise in a full overhead press (m): from about shoulder level with
    /// the forearm upright to the straight arm overhead.
    var fullPressTravel: Double {
        armLength * sin(overheadElevation * .pi / 180) - forearmLength
    }

    /// How far the hands drop in a squat to parallel (m): about a fifth of standing height.
    var parallelSquatTravel: Double { 0.2 * estimatedHeight }
}
