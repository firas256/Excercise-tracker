import Foundation

/// The guided poses of the calibration routine.
enum CalibrationPose: Int, CaseIterable, Codable, Sendable {
    case armsDown
    case armForward
    case palmUp
    case armSide
    case armOverhead

    var title: String {
        switch self {
        case .armsDown: return "Arms down"
        case .armForward: return "Arm forward"
        case .palmUp: return "Palm up"
        case .armSide: return "Arm to the side"
        case .armOverhead: return "Arm overhead"
        }
    }

    var instruction: String {
        switch self {
        case .armsDown: return "Stand tall. Let your watch arm hang relaxed by your side, palm facing your leg. Hold still."
        case .armForward: return "Raise the arm straight in front of you to shoulder height, palm facing the floor. Hold."
        case .palmUp: return "Keep the arm in front and turn your palm to face the ceiling. Hold."
        case .armSide: return "Move the arm out to your side at shoulder height, palm facing the floor. Hold."
        case .armOverhead: return "Reach the arm straight up above your head. Hold."
        }
    }

    var symbolName: String {
        switch self {
        case .armsDown: return "figure.stand"
        case .armForward: return "arrow.right.circle"
        case .palmUp: return "arrow.triangle.2.circlepath"
        case .armSide: return "figure.arms.open"
        case .armOverhead: return "arrow.up.circle"
        }
    }
}

enum CalibrationPhase: Equatable, Sendable {
    /// Waiting for the user to move into the pose.
    case waitingForMovement
    /// Moved – waiting for the arm to become still.
    case waitingForStillness
    /// Still – counting the hold (0...1).
    case holding(Double)
    /// Still, but the orientation does not match the instruction.
    case wrongPose(String)
    case finished
}

enum CalibrationEvent: Equatable {
    case stepStarted(CalibrationPose)
    case holdStarted
    case poseCaptured(CalibrationPose)
    case wrongPose(String)
    case finished(CalibrationProfile)
}

/// State machine for the calibration routine.
///
/// For every pose it waits for movement, then for stillness (low gyro & acceleration), holds for
/// a moment while averaging gravity, validates the orientation and moves on. From the captured
/// gravity directions it learns which watch axes correspond to the forearm and the palm.
final class CalibrationEngine {
    struct Settings {
        var holdDuration: Double = 1.2
        var stillRotation: Double = 0.3      // rad/s
        var stillAcceleration: Double = 0.06 // g
        var movementNeeded: Double = 0.5     // rad of accumulated rotation
    }

    let settings: Settings
    let wrist: WristSide
    let crownTowardsHand: Bool

    private(set) var stepIndex = 0
    private(set) var phase: CalibrationPhase = .waitingForMovement
    var currentPose: CalibrationPose? { stepIndex < CalibrationPose.allCases.count ? CalibrationPose.allCases[stepIndex] : nil }
    var progress: Double { Double(stepIndex) / Double(CalibrationPose.allCases.count) }

    private var lastT: Double?
    private var rotEMA = 0.0
    private var accEMA = 0.0
    private var movedSinceCapture = 0.0
    private var holdStart: Double?
    private var holdGravity = Vector3.zero
    private var holdAttitude: [Quaternion] = []
    private var holdNoise: [Double] = []
    private var holdCount = 0
    private var wrongPoseReported = false

    // Captured values
    private var forearm: Vector3?
    private var palm: Vector3?
    private var forwardGravity: Vector3?
    private var forwardHeading: Double?
    private var supination: Double?
    private var abduction: Double = 0
    private var overhead: Double?
    private var resting: Double?
    private var noise: [Double] = []
    /// +1 if `attitude.rotate` maps device → world, -1 if the conjugate does (decided from gravity).
    private var attitudeConvention: Double?

    init(wrist: WristSide = .unknown, crownTowardsHand: Bool = true, settings: Settings = Settings()) {
        self.wrist = wrist
        self.crownTowardsHand = crownTowardsHand
        self.settings = settings
    }

    func start() -> [CalibrationEvent] {
        stepIndex = 0
        phase = .waitingForStillness  // first pose needs no movement
        movedSinceCapture = 0
        return [.stepStarted(.armsDown)]
    }

    private var defaults: CalibrationProfile {
        CalibrationProfile.defaultProfile(wrist: wrist, crownTowardsHand: crownTowardsHand)
    }

    func ingest(_ s: MotionSample) -> [CalibrationEvent] {
        guard let pose = currentPose, phase != .finished else { return [] }
        let dt = lastT.map { max(0.001, min(0.2, s.timestamp - $0)) } ?? 0.02
        lastT = s.timestamp
        let a = dt / (0.2 + dt)
        rotEMA = a * s.rotationRate.length + (1 - a) * rotEMA
        accEMA = a * s.userAcceleration.length + (1 - a) * accEMA
        movedSinceCapture += s.rotationRate.length * dt
        if attitudeConvention == nil { attitudeConvention = detectConvention(s) }

        let still = rotEMA < settings.stillRotation && accEMA < settings.stillAcceleration
        var events: [CalibrationEvent] = []

        switch phase {
        case .waitingForMovement:
            if movedSinceCapture >= settings.movementNeeded { phase = .waitingForStillness }
        case .wrongPose:
            // Give the user a chance to adjust before measuring again.
            if movedSinceCapture >= settings.movementNeeded / 2 { phase = .waitingForStillness }
        case .waitingForStillness:
            if still {
                holdStart = s.timestamp
                holdGravity = .zero
                holdAttitude = []
                holdNoise = []
                holdCount = 0
                phase = .holding(0)
                events.append(.holdStarted)
            }
        case .holding:
            if !still {
                phase = .waitingForStillness
                holdStart = nil
                break
            }
            holdGravity += s.gravity
            holdAttitude.append(s.attitude)
            holdNoise.append(s.rotationRate.length)
            holdCount += 1
            let elapsed = s.timestamp - (holdStart ?? s.timestamp)
            phase = .holding(min(1, elapsed / settings.holdDuration))
            if elapsed >= settings.holdDuration, holdCount > 3 {
                let g = (holdGravity / Double(holdCount)).normalized
                let attitude = holdAttitude[holdAttitude.count / 2]
                if let problem = validateAndStore(pose: pose, gravity: g, attitude: attitude) {
                    // Accept on the second attempt so a user with an unusual setup is never stuck.
                    if wrongPoseReported {
                        forceStore(pose: pose, gravity: g, attitude: attitude)
                    } else {
                        wrongPoseReported = true
                        movedSinceCapture = 0
                        phase = .wrongPose(problem)
                        events.append(.wrongPose(problem))
                        return events
                    }
                }
                noise.append(SignalMath.mean(holdNoise))
                events.append(contentsOf: advance(from: pose))
            }
        case .finished:
            break
        }
        return events
    }

    /// Skips the current pose, falling back to defaults for whatever it would have measured.
    func skipCurrentStep() -> [CalibrationEvent] {
        guard let pose = currentPose else { return [] }
        return advance(from: pose)
    }

    private func advance(from pose: CalibrationPose) -> [CalibrationEvent] {
        var events: [CalibrationEvent] = [.poseCaptured(pose)]
        stepIndex += 1
        movedSinceCapture = 0
        wrongPoseReported = false
        holdStart = nil
        if let next = currentPose {
            phase = .waitingForMovement
            events.append(.stepStarted(next))
        } else {
            phase = .finished
            events.append(.finished(makeProfile()))
        }
        return events
    }

    // MARK: - Pose validation

    private func elevation(_ g: Vector3) -> Double {
        let f = forearm ?? defaults.forearmAxis
        return asin(SignalMath.clamp(-g.dot(f), -1, 1)) * 180 / .pi
    }

    /// Returns a user-facing problem description, or nil when the pose is OK (values stored).
    private func validateAndStore(pose: CalibrationPose, gravity g: Vector3, attitude: Quaternion) -> String? {
        switch pose {
        case .armsDown:
            // The watch x-axis runs along the forearm, so a hanging arm puts gravity on x.
            guard abs(g.x) >= 0.75 else { return "Let your arm hang straight down" }
            forearm = g
            resting = -90 + g.angle(to: g.x > 0 ? Vector3.unitX : -Vector3.unitX)
        case .armForward:
            guard abs(elevation(g)) <= 30 else { return "Raise your arm to shoulder height" }
            guard g.z < 0.3 else { return "Turn your palm to face the floor" }
            let f = forearm ?? defaults.forearmAxis
            palm = g.orthogonalized(against: f).normalized
            forwardGravity = g
            forwardHeading = heading(of: f, attitude: attitude)
        case .palmUp:
            let p = palm ?? defaults.palmAxis
            guard abs(elevation(g)) <= 35 else { return "Keep your arm at shoulder height" }
            guard g.dot(p) < -0.5 else { return "Rotate your palm to face up" }
            let f = forearm ?? defaults.forearmAxis
            if let fg = forwardGravity {
                supination = fg.orthogonalized(against: f).angle(to: g.orthogonalized(against: f))
            }
        case .armSide:
            let p = palm ?? defaults.palmAxis
            guard abs(elevation(g)) <= 35 else { return "Keep your arm at shoulder height" }
            guard g.dot(p) > 0.5 else { return "Palm facing the floor" }
            let f = forearm ?? defaults.forearmAxis
            if let h0 = forwardHeading, let h1 = heading(of: f, attitude: attitude) {
                let d = wrapDegrees(h1 - h0)
                guard abs(d) >= 35 else { return "Move your arm out to the side" }
                abduction = d > 0 ? 1 : -1
            }
        case .armOverhead:
            let e = elevation(g)
            guard e >= 50 else { return "Reach straight up overhead" }
            overhead = e
        }
        return nil
    }

    /// Stores values from a pose that failed validation twice (best effort).
    private func forceStore(pose: CalibrationPose, gravity g: Vector3, attitude: Quaternion) {
        switch pose {
        case .armsDown:
            forearm = g
        case .armForward:
            let f = forearm ?? defaults.forearmAxis
            let candidate = g.orthogonalized(against: f)
            if candidate.length > 0.5 { palm = candidate.normalized }
        case .armOverhead:
            overhead = elevation(g)
        default:
            break
        }
    }

    private func makeProfile() -> CalibrationProfile {
        var f = forearm ?? defaults.forearmAxis
        f = f.normalized
        var p = (palm ?? defaults.palmAxis).orthogonalized(against: f)
        if p.length < 0.3 { p = defaults.palmAxis.orthogonalized(against: f) }
        if p.length < 0.3 { p = Vector3.unitY.orthogonalized(against: f) }
        p = p.normalized
        return CalibrationProfile(
            forearmAxis: f,
            palmAxis: p,
            createdAt: Date(),
            wrist: wrist,
            overheadElevation: overhead ?? 80,
            restingElevation: resting ?? -88,
            supinationRange: supination ?? 170,
            stillnessNoise: noise.isEmpty ? 0.03 : SignalMath.mean(noise),
            abductionDirection: abduction
        )
    }

    // MARK: - Heading helpers

    private func detectConvention(_ s: MotionSample) -> Double? {
        guard s.attitude != .identity, s.gravity.length > 0.5 else { return nil }
        let down = Vector3(0, 0, -1)
        let direct = s.attitude.rotate(s.gravity.normalized).dot(down)
        let inverse = s.attitude.conjugate.rotate(s.gravity.normalized).dot(down)
        if direct > 0.9 { return 1 }
        if inverse > 0.9 { return -1 }
        return nil
    }

    private func heading(of deviceVector: Vector3, attitude: Quaternion) -> Double? {
        guard let c = attitudeConvention else { return nil }
        let q = c > 0 ? attitude : attitude.conjugate
        let w = q.rotate(deviceVector)
        let horizontal = (w.x * w.x + w.y * w.y).squareRoot()
        guard horizontal > 0.4 else { return nil }
        return atan2(w.y, w.x) * 180 / .pi
    }

    private func wrapDegrees(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }
}
