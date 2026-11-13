import Foundation

/// Uses the grip (how the forearm is turned, i.e. which way the watch faces) to rule exercises in
/// or out. Curls and pushdowns, for example, move the forearm through similar angles, but a curl is
/// done palm-up (watch face down) while a pushdown is palm-down on a bar or thumb-up on a rope
/// (watch face up or to the side).
///
/// The grip is read from the features' palm orientation while the forearm is roughly horizontal,
/// relative to the user's own calibrated palm-down and palm-up, so a forearm that doesn't turn a
/// full 180° still reads as "palm up" at its own limit.
enum GripModel {

    /// Grips an exercise is normally done with; nil = not judged (forearm mostly vertical, lying
    /// down, or any grip is common).
    static func grips(for exercise: ExerciseType) -> [Grip]? {
        switch exercise {
        case .bicepCurl: return [.supinated]
        case .hammerCurl: return [.neutral]
        case .tricepsPushdown: return [.pronated, .neutral]          // bar or rope
        case .lateralRaise, .frontRaise: return [.pronated, .neutral]
        case .uprightRow: return [.pronated]
        case .seatedCableRow, .chestPressMachine: return [.pronated, .neutral]
        case .tricepsKickback, .reverseFly: return [.neutral, .pronated]
        default: return nil
        }
    }

    /// Measured roll away from palm-down (0 palm down … 90 thumb up … ~180 palm up) and how
    /// consistent it was (0…1). nil when the forearm was rarely horizontal enough to tell.
    static func measuredRoll(_ f: MotionFeatures) -> (roll: Double, clarity: Double)? {
        guard let c = f.palmDown, let s = f.thumbUp else { return nil }
        let r = (c * c + s * s).squareRoot()
        guard r > 0.2 else { return nil }
        return (atan2(s, c) * 180 / .pi, min(1, r))
    }

    /// The roll on the user's own scale: the palm-up half (thumb up → as far as *their* forearm
    /// turns, measured in calibration) is stretched to 90°…180°, so their palm-up reads 180°.
    static func personalRoll(_ roll: Double, body: BodyProfile) -> Double {
        guard roll > 90 else { return roll }
        let palmUp = SignalMath.clamp(body.supinationRange, 120, 190)
        return min(200, 90 + (roll - 90) * 90 / (palmUp - 90))
    }

    /// The grip that best matches the measurement (for display / tests).
    static func grip(of f: MotionFeatures, body: BodyProfile = .typical) -> Grip? {
        guard let m = measuredRoll(f), m.clarity >= 0.5 else { return nil }
        let roll = personalRoll(m.roll, body: body)
        return Grip.allCases.min { abs(roll - $0.nominalRoll) < abs(roll - $1.nominalRoll) }
    }

    /// Likelihood factor (0.05…1) for an exercise given the measured grip.
    static func factor(for exercise: ExerciseType, features: MotionFeatures, body: BodyProfile) -> Double {
        guard let grips = grips(for: exercise), let m = measuredRoll(features) else { return 1 }
        let roll = personalRoll(m.roll, body: body)
        let match = grips.map { grip -> Double in
            let d = abs(roll - grip.nominalRoll)
            return exp(-0.5 * (d / 35) * (d / 35))
        }.max() ?? 1
        // Only trust a clear, steady grip reading.
        let trust = SignalMath.clamp((m.clarity - 0.3) / 0.4, 0, 1)
        return (1 - trust) + trust * max(0.05, match)
    }

    /// Re-weights classifier candidates by grip compatibility.
    static func apply(_ candidates: [ExerciseCandidate], features: MotionFeatures?, body: BodyProfile) -> [ExerciseCandidate] {
        guard let features, !candidates.isEmpty else { return candidates }
        let weighted = candidates.map { c in
            ExerciseCandidate(exercise: c.exercise, probability: c.probability * factor(for: c.exercise, features: features, body: body))
        }
        let total = weighted.reduce(0) { $0 + $1.probability }
        guard total > 0 else { return candidates }
        return weighted.map { ExerciseCandidate(exercise: $0.exercise, probability: $0.probability / total) }
            .sorted { $0.probability > $1.probability }
    }
}
