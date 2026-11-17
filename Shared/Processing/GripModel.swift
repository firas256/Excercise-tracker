import Foundation

/// Uses the grip (how the forearm is turned, i.e. which way the watch faces) to weigh exercises.
/// Curls and pushdowns, for example, move the forearm through similar angles, but a curl is usually
/// done palm-up (watch face down) while a pushdown is usually palm-down on a bar or thumb-up on a rope
/// (watch face up or to the side).
///
/// "Usually": real lifters also do underhand pushdowns, reverse curls and so on, so a grip that's
/// unusual for an exercise is a soft penalty, not a veto – and once the user has confirmed sets of an
/// exercise with a grip, that grip counts as normal for them.
///
/// The grip is read from the features' palm orientation while the forearm is roughly horizontal,
/// relative to the user's own calibrated palm-down and palm-up, so a forearm that doesn't turn a
/// full 180° still reads as "palm up" at its own limit.
enum GripModel {

    /// How common each grip is for an exercise (1 = typical); nil = not judged (forearm mostly
    /// vertical, lying down, or any grip is common).
    static func grips(for exercise: ExerciseType) -> [(grip: Grip, weight: Double)]? {
        switch exercise {
        case .bicepCurl: return [(.supinated, 1), (.neutral, 0.35), (.pronated, 0.15)]           // reverse curls exist
        case .hammerCurl: return [(.neutral, 1), (.supinated, 0.3), (.pronated, 0.2)]
        case .tricepsPushdown: return [(.pronated, 1), (.neutral, 1), (.supinated, 0.5)]        // bar, rope, underhand
        case .lateralRaise, .frontRaise: return [(.pronated, 1), (.neutral, 0.8), (.supinated, 0.2)]
        case .uprightRow: return [(.pronated, 1), (.neutral, 0.4)]
        case .seatedCableRow, .chestPressMachine: return [(.pronated, 1), (.neutral, 1), (.supinated, 0.4)]
        case .tricepsKickback, .reverseFly: return [(.neutral, 1), (.pronated, 1), (.supinated, 0.3)]
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

    /// Confirmed sets with a similar grip needed before that grip is normal for the user.
    static let examplesForOwnGrip = 3

    private static func closeness(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return exp(-0.5 * (d / 35) * (d / 35))
    }

    /// Likelihood factor (0.05…1) for an exercise given the measured grip. Grips the user has
    /// confirmed for this exercise before (`personal`) count as typical.
    static func factor(for exercise: ExerciseType, features: MotionFeatures, body: BodyProfile,
                       personal: ClassifierPersonalization? = nil) -> Double {
        guard let grips = grips(for: exercise), let m = measuredRoll(features) else { return 1 }
        let roll = personalRoll(m.roll, body: body)
        var match = grips.map { $0.weight * closeness(roll, $0.grip.nominalRoll) }.max() ?? 1
        // A grip counts as the user's own once they've confirmed several sets with it (a single,
        // possibly mislabelled set shouldn't make it normal).
        let similar = (personal?.examples[exercise] ?? []).filter { example in
            guard let e = measuredRoll(example), e.clarity >= 0.5 else { return false }
            return abs(personalRoll(e.roll, body: body) - roll) <= 35
        }
        if similar.count >= examplesForOwnGrip { match = 1 }
        // Only trust a clear, steady grip reading.
        let trust = SignalMath.clamp((m.clarity - 0.3) / 0.4, 0, 1)
        return (1 - trust) + trust * max(0.05, match)
    }

    /// Re-weights classifier candidates by grip compatibility.
    static func apply(_ candidates: [ExerciseCandidate], features: MotionFeatures?, body: BodyProfile,
                      personal: ClassifierPersonalization? = nil) -> [ExerciseCandidate] {
        guard let features, !candidates.isEmpty else { return candidates }
        let weighted = candidates.map { c in
            ExerciseCandidate(exercise: c.exercise,
                              probability: c.probability * factor(for: c.exercise, features: features, body: body, personal: personal))
        }
        let total = weighted.reduce(0) { $0 + $1.probability }
        guard total > 0 else { return candidates }
        return weighted.map { ExerciseCandidate(exercise: $0.exercise, probability: $0.probability / total) }
            .sorted { $0.probability > $1.probability }
    }
}
