import Foundation

/// Everything the iPhone needs to show the workout live while the watch does the sensing.
struct LiveWorkoutState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case waitingForSet
        case inSet
        case reviewing
        case ended
    }

    var status: Status
    var repCount: Int
    var liveCue: String?
    var lastRepFlagged: Bool
    /// Top guesses for the current set (empty when the exercise is locked).
    var candidates: [ExerciseCandidate]
    var lockedExercise: ExerciseType?
    var completedSets: Int
    var restStartedAt: Date?
    var workoutStartedAt: Date?
    var heartRate: Double?
    var activeEnergy: Double
    /// A finished set waiting to be confirmed (on the phone or the watch).
    var pendingSet: PendingSetSummary?

    static let idle = LiveWorkoutState(status: .waitingForSet, repCount: 0, liveCue: nil, lastRepFlagged: false,
                                       candidates: [], lockedExercise: nil, completedSets: 0, restStartedAt: nil,
                                       workoutStartedAt: nil, heartRate: nil, activeEnergy: 0, pendingSet: nil)

    var currentGuess: ExerciseType? { lockedExercise ?? candidates.first?.exercise }
}

struct PendingSetSummary: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var exercise: ExerciseType?
    var candidates: [ExerciseCandidate]
    var repCount: Int
    var feedback: SetFeedback
    var weight: Double?
    var weightUnit: String
}

/// Requests from the iPhone to the watch.
enum WatchCommand: Codable, Equatable, Sendable {
    case lockExercise(ExerciseType?)
    case endSet
    case discardSet
    case savePendingSet(id: UUID, exercise: ExerciseType?, reps: Int, weight: Double?)
    case discardPendingSet(id: UUID)
    case endWorkout
    case requestState
}

extension SyncKeys {
    static let liveWorkout = "liveWorkout"
    static let motionFrames = "motionFrames"
    static let command = "command"
}

/// One frame of arm motion for the 3-D view: forearm direction (elevation + heading), palm roll
/// and how far the hand has moved up or down.
struct MotionFrame: Codable, Equatable, Sendable {
    /// Seconds (monotonic, same clock as the samples).
    var t: Double
    /// Forearm angle above horizontal, degrees (-90 = pointing down).
    var elevation: Double
    /// Forearm heading around the vertical axis, degrees (integrated gyro, relative).
    var heading: Double
    /// Palm roll, degrees (0 = palm down, ±180 = palm up).
    var roll: Double
    /// Wrist height relative to its recent average, cm.
    var lift: Double
    /// How far the elbow (the whole arm) moved up or down, cm: the part of `lift` that the forearm
    /// turning about the elbow doesn't explain. ~0 for a curl, large for a press or a squat.
    var elbowLift: Double = 0

    /// Unit vector of the forearm (elbow → hand) in a world frame: x forward, y left, z up.
    var forearmDirection: Vector3 {
        let e = elevation * .pi / 180, h = heading * .pi / 180
        return Vector3(cos(e) * cos(h), cos(e) * sin(h), sin(e))
    }

    /// Unit vector out of the palm, perpendicular to the forearm.
    var palmDirection: Vector3 {
        let f = forearmDirection
        // "Down" perpendicular to the forearm (palm-down reference); fall back for a vertical forearm.
        var down = Vector3(0, 0, -1).orthogonalized(against: f)
        if down.length < 0.2 {
            let h = heading * .pi / 180
            down = Vector3(cos(h), sin(h), 0) * (elevation > 0 ? 1 : -1)
        }
        down = down.normalized
        let side = f.cross(down).normalized
        let r = roll * .pi / 180
        return (down * cos(r) + side * sin(r)).normalized
    }
}

/// Turns the arm-frame sample stream into `MotionFrame`s. Heading is the integrated rotation about
/// vertical (with a slow leak so it re-centres), lift is double-integrated vertical acceleration
/// with leaky integrators (good enough to *see* presses and squats, not for measuring).
///
/// The elbow's own movement is the lift minus the wrist height the forearm's rotation accounts
/// for (watch ~26 cm from the elbow); that rotation height goes through the very same leaky
/// integrators, so both carry the same filtering and the difference is only real translation.
final class MotionFrameBuilder {
    let outputRate: Double
    /// Elbow → watch distance, metres.
    static let watchRadius = 0.26
    private var lastT: Double?
    private var heading = 0.0
    private var velocity = 0.0
    private var position = 0.0
    private var lastRotationHeight: Double?
    private var lastRotationSpeed: Double?
    private var rotationVelocity = 0.0
    private var rotationPosition = 0.0
    private var nextEmit: Double?

    init(outputRate: Double = 15) {
        self.outputRate = outputRate
    }

    func reset() {
        lastT = nil
        heading = 0
        velocity = 0
        position = 0
        lastRotationHeight = nil
        lastRotationSpeed = nil
        rotationVelocity = 0
        rotationPosition = 0
        nextEmit = nil
    }

    /// Feeds one sample; returns a frame whenever one is due at `outputRate`.
    func add(_ s: ArmSample) -> MotionFrame? {
        let dt = lastT.map { max(0.001, min(0.2, s.t - $0)) } ?? 0
        lastT = s.t
        heading += s.yawRate * 180 / .pi * dt
        heading *= exp(-dt / 30)
        let decay = exp(-dt / 1.0)
        velocity = velocity * decay + s.verticalAcceleration * dt
        position = position * decay + velocity * dt
        // Wrist height from the forearm's angle alone, fed through the same integrators as its
        // acceleration (the change in its speed).
        let rotationHeight = Self.watchRadius * sin(s.elevation * .pi / 180)
        if let lastHeight = lastRotationHeight, dt > 0 {
            let speed = (rotationHeight - lastHeight) / dt
            rotationVelocity = rotationVelocity * decay + (speed - (lastRotationSpeed ?? speed))
            rotationPosition = rotationPosition * decay + rotationVelocity * dt
            lastRotationSpeed = speed
        }
        lastRotationHeight = rotationHeight
        if let next = nextEmit, s.t + 1e-6 < next { return nil }
        // Schedule from the previous due time (not this sample) so rounding never skips frames.
        let step = 1 / outputRate
        nextEmit = max((nextEmit ?? s.t) + step, s.t + step / 2)
        return MotionFrame(t: s.t, elevation: s.elevation, heading: heading, roll: s.roll, lift: position * 100,
                           elbowLift: (position - rotationPosition) * 100)
    }

    /// Frames for a whole recording (used for replay on the iPhone).
    static func frames(from samples: [ArmSample], outputRate: Double = 25) -> [MotionFrame] {
        let b = MotionFrameBuilder(outputRate: outputRate)
        return samples.compactMap { b.add($0) }
    }
}
