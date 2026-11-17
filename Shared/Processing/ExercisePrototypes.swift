import Foundation

struct FeatureGaussian: Codable, Equatable, Sendable {
    var mean: Double
    var sd: Double
}

/// Biomechanical "fingerprint" of an exercise as seen from a wrist sensor, written as a Gaussian
/// per feature. These are hand-made starting points derived from how each movement moves the
/// forearm; the classifier personalises them from your own confirmed sets.
struct ExercisePrototype: Sendable {
    var exercise: ExerciseType
    var prior: Double
    var stats: [MotionFeatures.Key: FeatureGaussian]
}

enum ExercisePrototypes {

    /// Typical spread used when a prototype does not specify one.
    static func defaultSD(_ key: MotionFeatures.Key) -> Double {
        switch key {
        case .startElevation, .peakElevation, .lowElevation, .highElevation: return 18
        case .upTempoBias: return 0.3
        case .pivotRadius: return 10
        case .palmDown: return 0.4
        case .thumbUp: return 0.35
        case .axisTwist, .axisPalm, .axisRadial: return 0.3
        case .rotationAmplitude: return 35
        case .yawAmplitude: return 25
        case .verticalAmplitude, .forearmAmplitude: return 15
        case .startsHigh: return 0.3
        case .pushDirection: return 0.5
        case .repPeriod: return 1.2
        }
    }

    /// Lower bound for a personalised spread, so a handful of examples cannot make a class over-confident.
    static func minimumSD(_ key: MotionFeatures.Key) -> Double {
        switch key {
        case .startElevation, .peakElevation, .lowElevation, .highElevation: return 6
        case .upTempoBias: return 0.12
        case .pivotRadius: return 4
        case .palmDown, .thumbUp: return 0.15
        case .axisTwist, .axisPalm, .axisRadial: return 0.12
        case .rotationAmplitude: return 10
        case .yawAmplitude: return 8
        case .verticalAmplitude, .forearmAmplitude: return 5
        case .startsHigh: return 0.15
        case .pushDirection: return 0.2
        case .repPeriod: return 0.3
        }
    }

    /// Relative importance of each feature in the classifier.
    static func weight(_ key: MotionFeatures.Key) -> Double {
        switch key {
        // Where a rep "starts" depends on how the set began (e.g. a pushdown begun with the arms
        // hanging looks like it starts low, like a curl), so the angles are compared as the lowest
        // and highest point of the rep instead, and the starting side counts only a little.
        case .startElevation, .peakElevation: return 0
        case .lowElevation, .highElevation: return 1.0
        case .startsHigh: return 0.3
        case .palmDown: return 0.7
        case .thumbUp: return 0.5
        case .axisTwist, .axisPalm, .axisRadial: return 0.4
        case .rotationAmplitude, .yawAmplitude, .verticalAmplitude: return 0.6
        case .forearmAmplitude: return 0.4
        case .pushDirection: return 0.5
        case .repPeriod: return 0.3
        case .upTempoBias: return 0.5
        case .pivotRadius: return 0.8
        }
    }

    /// Which joint the watch swings around, so the swing radius can be compared with the user's
    /// own forearm or arm length.
    enum Pivot { case elbow, shoulder }

    static func pivot(_ e: ExerciseType) -> Pivot? {
        switch e {
        case .bicepCurl, .hammerCurl, .tricepsPushdown, .overheadTricepsExtension, .skullCrusher, .tricepsKickback:
            return .elbow
        case .lateralRaise, .frontRaise, .reverseFly, .chestFly:
            return .shoulder
        default:
            return nil
        }
    }

    /// Which half of the rep is the quicker, effortful one: +1 rising, -1 lowering.
    static func effortDirection(_ e: ExerciseType) -> Double? {
        switch e {
        case .bicepCurl, .hammerCurl, .lateralRaise, .frontRaise, .shoulderPress, .uprightRow, .shrug,
             .overheadTricepsExtension, .skullCrusher, .benchPress, .bentOverRow, .deadlift, .romanianDeadlift,
             .squat, .gobletSquat, .tricepsKickback, .reverseFly:
            return 1
        case .tricepsPushdown, .latPulldown:
            return -1
        default:
            return nil
        }
    }

    private typealias K = MotionFeatures.Key

    private static func make(_ e: ExerciseType, prior: Double, _ values: [K: (Double, Double?)]) -> ExercisePrototype {
        var stats: [K: FeatureGaussian] = [:]
        for (k, v) in values {
            stats[k] = FeatureGaussian(mean: v.0, sd: v.1 ?? defaultSD(k))
        }
        // Exercises done with more than one grip (bar or rope pushdown…) can't be described by one
        // average palm orientation; `GripModel` judges their grip instead.
        if (GripModel.grips(for: e)?.filter { $0.weight >= 0.5 }.count ?? 0) > 1 {
            stats[.palmDown] = nil
            stats[.thumbUp] = nil
        }
        if let a = stats[.startElevation], let b = stats[.peakElevation] {
            stats[.lowElevation] = a.mean <= b.mean ? a : b
            stats[.highElevation] = a.mean <= b.mean ? b : a
        }
        if let direction = effortDirection(e) {
            stats[.upTempoBias] = FeatureGaussian(mean: 0.2 * direction, sd: 0.3)
        }
        return ExercisePrototype(exercise: e, prior: prior, stats: stats)
    }

    static let all: [ExercisePrototype] = [
        make(.bicepCurl, prior: 1.0, [
            .startElevation: (-80, 12), .peakElevation: (40, 20), .palmDown: (-0.8, nil), .thumbUp: (0.25, nil),
            .axisRadial: (0.85, 0.25), .axisPalm: (0.3, nil), .axisTwist: (0.2, 0.25),
            .rotationAmplitude: (120, nil), .yawAmplitude: (15, 20), .verticalAmplitude: (45, nil),
            .forearmAmplitude: (8, nil), .startsHigh: (0.1, nil), .repPeriod: (3, nil),
        ]),
        make(.hammerCurl, prior: 0.8, [
            .startElevation: (-80, 12), .peakElevation: (40, 20), .palmDown: (0, 0.35), .thumbUp: (0.9, 0.25),
            .axisRadial: (0.3, nil), .axisPalm: (0.85, 0.25), .axisTwist: (0.2, 0.25),
            .rotationAmplitude: (120, nil), .yawAmplitude: (15, 20), .verticalAmplitude: (45, nil),
            .forearmAmplitude: (8, nil), .startsHigh: (0.1, nil), .repPeriod: (3, nil),
        ]),
        // Forearm angle: upright for a strict dumbbell press, but often 30–55° with the elbows
        // forward or on a machine (seen in real recordings), hence the wide spread.
        make(.shoulderPress, prior: 1.0, [
            .startElevation: (45, 22), .peakElevation: (68, 18), .rotationAmplitude: (25, 20),
            .yawAmplitude: (10, 15), .verticalAmplitude: (40, nil), .forearmAmplitude: (35, nil),
            .startsHigh: (0.1, nil), .pushDirection: (0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.lateralRaise, prior: 1.0, [
            .startElevation: (-80, 12), .peakElevation: (-5, 15), .palmDown: (0.8, nil), .thumbUp: (0.3, 0.4),
            .axisRadial: (0.85, nil), .rotationAmplitude: (80, 25), .yawAmplitude: (15, 20),
            .verticalAmplitude: (50, nil), .forearmAmplitude: (8, nil), .startsHigh: (0.1, nil), .repPeriod: (3, nil),
        ]),
        make(.frontRaise, prior: 0.6, [
            .startElevation: (-80, 12), .peakElevation: (10, 15), .palmDown: (0.7, nil), .thumbUp: (0.3, 0.4),
            .axisRadial: (0.85, nil), .rotationAmplitude: (90, 25), .yawAmplitude: (15, 20),
            .verticalAmplitude: (55, nil), .forearmAmplitude: (8, nil), .startsHigh: (0.1, nil), .repPeriod: (3, nil),
        ]),
        make(.uprightRow, prior: 0.5, [
            .startElevation: (-82, 12), .peakElevation: (-35, 18), .palmDown: (0, 0.5), .thumbUp: (0.5, 0.4),
            .rotationAmplitude: (55, 25), .yawAmplitude: (15, 20), .verticalAmplitude: (40, nil),
            .forearmAmplitude: (15, nil), .startsHigh: (0.1, nil), .pushDirection: (-0.5, 0.6), .repPeriod: (2.5, nil),
        ]),
        make(.shrug, prior: 0.6, [
            .startElevation: (-86, 8), .peakElevation: (-85, 8), .rotationAmplitude: (6, 8), .yawAmplitude: (5, 8),
            .verticalAmplitude: (8, 5), .forearmAmplitude: (8, 5), .startsHigh: (0.1, nil),
            .pushDirection: (-0.9, nil), .repPeriod: (2, 1),
        ]),
        make(.benchPress, prior: 1.0, [
            .startElevation: (84, 10), .peakElevation: (78, 12), .rotationAmplitude: (15, 15), .yawAmplitude: (8, 12),
            .verticalAmplitude: (38, nil), .forearmAmplitude: (35, nil), .startsHigh: (0.9, nil),
            .pushDirection: (-0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.chestFly, prior: 0.6, [
            .startElevation: (80, 15), .peakElevation: (5, 25), .palmDown: (-0.6, 0.5), .thumbUp: (0.4, 0.4),
            .axisRadial: (0.7, 0.35), .rotationAmplitude: (75, 25), .yawAmplitude: (10, 15),
            .verticalAmplitude: (40, nil), .forearmAmplitude: (10, nil), .startsHigh: (0.9, nil), .repPeriod: (3.5, nil),
        ]),
        make(.bentOverRow, prior: 0.9, [
            .startElevation: (-85, 8), .peakElevation: (-65, 18), .rotationAmplitude: (30, 20), .yawAmplitude: (10, 12),
            .verticalAmplitude: (28, 12), .forearmAmplitude: (25, 12), .startsHigh: (0.1, nil),
            .pushDirection: (-0.9, nil), .repPeriod: (2.5, nil),
        ]),
        make(.deadlift, prior: 0.9, [
            .startElevation: (-87, 8), .peakElevation: (-85, 10), .rotationAmplitude: (10, 12), .yawAmplitude: (8, 12),
            .verticalAmplitude: (50, nil), .forearmAmplitude: (48, nil), .startsHigh: (0.1, nil),
            .pushDirection: (-0.9, nil), .repPeriod: (4, 1.5),
        ]),
        make(.romanianDeadlift, prior: 0.8, [
            .startElevation: (-87, 8), .peakElevation: (-84, 10), .rotationAmplitude: (15, 15), .yawAmplitude: (8, 12),
            .verticalAmplitude: (40, nil), .forearmAmplitude: (38, nil), .startsHigh: (0.9, nil),
            .pushDirection: (0.9, nil), .repPeriod: (4, 1.5),
        ]),
        make(.squat, prior: 0.9, [
            .startElevation: (35, 25), .peakElevation: (35, 25), .rotationAmplitude: (15, 15), .yawAmplitude: (8, 12),
            .verticalAmplitude: (50, nil), .forearmAmplitude: (30, 18), .startsHigh: (0.9, nil),
            .pushDirection: (-0.5, 0.7), .repPeriod: (3.5, nil),
        ]),
        make(.gobletSquat, prior: 0.7, [
            .startElevation: (70, 15), .peakElevation: (70, 15), .rotationAmplitude: (12, 15), .yawAmplitude: (8, 12),
            .verticalAmplitude: (50, nil), .forearmAmplitude: (45, nil), .startsHigh: (0.9, nil),
            .pushDirection: (-0.9, nil), .repPeriod: (3.5, nil),
        ]),
        make(.lunge, prior: 0.6, [
            .startElevation: (-86, 8), .peakElevation: (-85, 8), .rotationAmplitude: (10, 12), .yawAmplitude: (10, 12),
            .verticalAmplitude: (35, nil), .forearmAmplitude: (33, nil), .startsHigh: (0.9, nil),
            .pushDirection: (0.9, nil), .repPeriod: (3.5, nil),
        ]),
        make(.overheadTricepsExtension, prior: 0.7, [
            .startElevation: (78, 12), .peakElevation: (-35, 25), .palmDown: (-0.5, 0.6), .thumbUp: (0.5, 0.5),
            .rotationAmplitude: (110, nil), .yawAmplitude: (10, 15), .verticalAmplitude: (35, nil),
            .forearmAmplitude: (8, nil), .startsHigh: (0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.skullCrusher, prior: 0.5, [
            .startElevation: (82, 12), .peakElevation: (-5, 25), .palmDown: (-0.6, 0.5), .thumbUp: (0.3, 0.4),
            .axisRadial: (0.8, nil), .rotationAmplitude: (90, 30), .yawAmplitude: (8, 12),
            .verticalAmplitude: (28, 12), .forearmAmplitude: (8, nil), .startsHigh: (0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.kettlebellSwing, prior: 0.5, [
            .startElevation: (-75, 20), .peakElevation: (0, 25), .palmDown: (0.2, 0.6),
            .rotationAmplitude: (100, nil), .yawAmplitude: (10, 15), .verticalAmplitude: (60, 20),
            .forearmAmplitude: (15, 20), .startsHigh: (0.1, nil), .repPeriod: (1.4, 0.4),
        ]),
        make(.latPulldown, prior: 1.0, [
            .startElevation: (80, 10), .peakElevation: (70, 15), .rotationAmplitude: (20, 15), .yawAmplitude: (8, 12),
            .verticalAmplitude: (45, nil), .forearmAmplitude: (42, nil), .startsHigh: (0.9, nil),
            .pushDirection: (-0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.seatedCableRow, prior: 0.9, [
            .startElevation: (0, 20), .peakElevation: (0, 20), .palmDown: (0, 0.4), .thumbUp: (0.85, 0.3),
            .rotationAmplitude: (20, 15), .yawAmplitude: (15, 15), .verticalAmplitude: (8, 8),
            .forearmAmplitude: (35, nil), .pushDirection: (-0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.chestPressMachine, prior: 0.8, [
            .startElevation: (5, 20), .peakElevation: (5, 20), .palmDown: (0.4, 0.6), .thumbUp: (0.5, 0.5),
            .rotationAmplitude: (15, 15), .yawAmplitude: (10, 12), .verticalAmplitude: (8, 8),
            .forearmAmplitude: (35, nil), .pushDirection: (0.9, nil), .repPeriod: (3, nil),
        ]),
        make(.pecDeck, prior: 0.8, [
            .startElevation: (50, 40), .peakElevation: (50, 40), .rotationAmplitude: (65, 25), .yawAmplitude: (60, 25),
            .verticalAmplitude: (8, 10), .forearmAmplitude: (10, 12), .repPeriod: (3, nil),
        ]),
        make(.tricepsPushdown, prior: 1.0, [
            .startElevation: (15, 20), .peakElevation: (-75, 15), .palmDown: (0.6, 0.5), .thumbUp: (0.4, 0.5),
            .rotationAmplitude: (90, 30), .yawAmplitude: (8, 12), .verticalAmplitude: (35, nil),
            .forearmAmplitude: (8, nil), .startsHigh: (0.9, nil), .repPeriod: (2.5, nil),
        ]),
        make(.legPress, prior: 0.3, [
            .startElevation: (-60, 35), .peakElevation: (-60, 35), .rotationAmplitude: (8, 10), .yawAmplitude: (5, 8),
            .verticalAmplitude: (5, 5), .forearmAmplitude: (5, 5), .repPeriod: (3, nil),
        ]),
        make(.legExtension, prior: 0.3, [
            .startElevation: (-60, 35), .peakElevation: (-60, 35), .rotationAmplitude: (8, 10), .yawAmplitude: (5, 8),
            .verticalAmplitude: (5, 5), .forearmAmplitude: (5, 5), .repPeriod: (3, nil),
        ]),
        make(.legCurl, prior: 0.3, [
            .startElevation: (-60, 35), .peakElevation: (-60, 35), .rotationAmplitude: (8, 10), .yawAmplitude: (5, 8),
            .verticalAmplitude: (5, 5), .forearmAmplitude: (5, 5), .repPeriod: (3, nil),
        ]),
        make(.pullUp, prior: 0.5, [
            .startElevation: (85, 10), .peakElevation: (75, 15), .rotationAmplitude: (25, 20),
            .verticalAmplitude: (10, 10), .forearmAmplitude: (10, 10), .startsHigh: (0.1, nil), .repPeriod: (3, nil),
        ]),
        make(.pushUp, prior: 0.5, [
            .startElevation: (-80, 12), .peakElevation: (-50, 20), .rotationAmplitude: (30, 20),
            .verticalAmplitude: (10, 10), .startsHigh: (0.9, nil), .repPeriod: (2.5, nil),
        ]),
        make(.dip, prior: 0.5, [
            .startElevation: (-85, 10), .peakElevation: (-70, 15), .rotationAmplitude: (20, 15),
            .verticalAmplitude: (10, 10), .startsHigh: (0.9, nil), .repPeriod: (2.5, nil),
        ]),
    ]

    static func prototype(for e: ExerciseType) -> ExercisePrototype? {
        all.first { $0.exercise == e }
    }
}
