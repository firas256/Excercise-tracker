import Foundation

/// Which motion signal was used to segment repetitions (and therefore the unit of range of motion).
enum RepSignalKind: String, Codable, Sendable {
    /// Forearm angle relative to gravity – drift free, best for curls/raises/extensions.
    case elevation
    /// Integrated rotation about the dominant axis – for twisting / horizontal arcs (e.g. pec deck).
    case rotation
    /// Vertical hand travel – for presses, squats, deadlifts, pulldowns.
    case vertical
    /// Hand travel along the forearm – for horizontal pushes/pulls (rows, chest press).
    case forearm

    var unit: RangeUnit {
        switch self {
        case .elevation, .rotation: return .degrees
        case .vertical, .forearm: return .centimeters
        }
    }
}

enum RangeUnit: String, Codable, Sendable {
    case degrees
    case centimeters

    var symbol: String { self == .degrees ? "°" : " cm" }
}

enum RepIssue: String, Codable, CaseIterable, Sendable {
    case partialRange
    case incompleteTop
    case incompleteBottom
    case rushedLift
    case rushedLowering
    case momentum
    case slowingDown

    var shortText: String {
        switch self {
        case .partialRange: return "Partial rep"
        case .incompleteTop: return "Go higher"
        case .incompleteBottom: return "Full extension"
        case .rushedLift: return "Too fast up"
        case .rushedLowering: return "Control the negative"
        case .momentum: return "Swinging"
        case .slowingDown: return "Slowing down"
        }
    }
}

/// Measurements for a single repetition.
struct RepMetrics: Codable, Equatable, Identifiable, Sendable {
    var id: Int { index }
    var index: Int
    /// Seconds from set start.
    var startTime: Double
    var duration: Double
    /// Duration of the lifting (concentric) phase in seconds.
    var concentricDuration: Double
    /// Duration of the lowering (eccentric) phase in seconds.
    var eccentricDuration: Double
    /// Range of motion in `unit`.
    var rangeOfMotion: Double
    var unit: RangeUnit
    /// Range relative to the set's reference range (1.0 = full).
    var rangeFraction: Double
    /// Average speed of the lifting phase (unit per second).
    var meanConcentricSpeed: Double
    /// Peak speed during the rep (unit per second).
    var peakSpeed: Double
    /// Forearm elevation (degrees) at the start and at the turnaround of the rep.
    var startElevation: Double
    var peakElevation: Double
    var issues: [RepIssue]
    /// 0...100
    var score: Int
}

enum FeedbackKind: String, Codable, Sendable {
    case positive
    case warning
    case info
}

struct FeedbackTip: Codable, Equatable, Hashable, Sendable {
    var kind: FeedbackKind
    var title: String
    var detail: String
}

/// Set-level summary produced by the feedback engine.
struct SetFeedback: Codable, Equatable, Sendable {
    var score: Int
    var averageRange: Double
    var unit: RangeUnit
    /// Coefficient of variation of the range of motion (0.05 = very consistent).
    var rangeVariation: Double
    var averageConcentric: Double
    var averageEccentric: Double
    /// Drop of lifting speed from the fastest early rep to the last rep (0.3 = 30% slower).
    var velocityLoss: Double
    var tips: [FeedbackTip]

    static let empty = SetFeedback(score: 0, averageRange: 0, unit: .degrees, rangeVariation: 0,
                                   averageConcentric: 0, averageEccentric: 0, velocityLoss: 0, tips: [])
}

struct ExerciseCandidate: Codable, Equatable, Hashable, Sendable {
    var exercise: ExerciseType
    var probability: Double
}

/// One completed set.
struct SetRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var exercise: ExerciseType
    /// What the watch guessed before any user correction (nil if the user picked it up front).
    var detectedExercise: ExerciseType?
    var detectionConfidence: Double
    var alternatives: [ExerciseCandidate]
    var userCorrectedExercise: Bool
    /// Final rep count (after an optional manual correction).
    var repCount: Int
    var detectedRepCount: Int
    var reps: [RepMetrics]
    var feedback: SetFeedback
    var signal: RepSignalKind
    var weight: Double?
    var weightUnit: String
    var startDate: Date
    var endDate: Date
    /// Feature vector used for classification (kept so the classifier can learn from corrections).
    var features: MotionFeatures?

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}

struct WorkoutRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var sets: [SetRecord]
    var averageHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var calibratedAt: Date?

    var totalReps: Int { sets.reduce(0) { $0 + $1.repCount } }
    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    var exercises: [ExerciseType] {
        var seen: [ExerciseType] = []
        for s in sets where !seen.contains(s.exercise) { seen.append(s.exercise) }
        return seen
    }
    var averageScore: Int {
        guard !sets.isEmpty else { return 0 }
        return sets.reduce(0) { $0 + $1.feedback.score } / sets.count
    }
}
