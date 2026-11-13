import Combine
import Foundation
import WatchKit

/// Drives the guided calibration: streams motion into `CalibrationEngine`, publishes the current
/// instruction/phase for the UI, plays a haptic for every state change and mirrors the progress
/// to the iPhone (big screen + spoken instructions). If the phone isn't reachable, the watch
/// speaks the instructions itself.
final class CalibrationViewModel: ObservableObject {
    @Published private(set) var pose: CalibrationPose = .armsDown
    @Published private(set) var phase: CalibrationPhase = .waitingForStillness
    @Published private(set) var stepIndex = 0
    @Published private(set) var isRunning = false
    @Published private(set) var phoneIsShowingInstructions = false

    var onFinish: ((CalibrationProfile) -> Void)?

    /// The workout session that keeps haptics and phone updates going with the wrist down; its
    /// problems (if any) are passed on to the phone.
    weak var session: WorkoutSessionService? {
        didSet {
            issueObserver = session?.$backgroundIssue.removeDuplicates().dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.resendToPhone() }
            }
        }
    }
    private var issueObserver: AnyCancellable?

    private let motion: MotionService
    private var engine = CalibrationEngine()
    private var lastPublishedKey = ""
    private var lastSentState: CalibrationLiveState?

    init(motion: MotionService = .shared) {
        self.motion = motion
    }

    static var currentWearing: (wrist: WristSide, crownTowardsHand: Bool) {
        let device = WKInterfaceDevice.current()
        let wrist: WristSide = device.wristLocation == .left ? .left : .right
        let crownRight = device.crownOrientation == .right
        return (wrist, (wrist == .left && crownRight) || (wrist == .right && !crownRight))
    }

    func start() {
        let wearing = Self.currentWearing
        let engine = CalibrationEngine(wrist: wearing.wrist, crownTowardsHand: wearing.crownTowardsHand)
        isRunning = true
        lastSentState = nil
        lastPublishedKey = ""
        motion.queue.async {
            self.engine = engine
            let events = engine.start()
            let phase = engine.phase
            DispatchQueue.main.async { self.apply(events, phase: phase, step: engine.stepIndex) }
        }
        motion.simulationScenario = .calibration
        motion.start { [weak self] sample in
            guard let self else { return }
            let events = self.engine.ingest(sample)
            let phase = self.engine.phase
            if !events.isEmpty || self.shouldPublish(phase) {
                let step = self.engine.stepIndex
                DispatchQueue.main.async { self.apply(events, phase: phase, step: step) }
            }
        }
    }

    func skipStep() {
        motion.queue.async {
            let events = self.engine.skipCurrentStep()
            let phase = self.engine.phase
            let step = self.engine.stepIndex
            DispatchQueue.main.async { self.apply(events, phase: phase, step: step) }
        }
    }

    func cancel() {
        motion.stop()
        if isRunning {
            WatchConnectivityService.shared.sendLive(.cancelled(step: stepIndex, pose: pose))
        }
        isRunning = false
        Speaker.shared.stop()
    }

    /// Publishes phase changes, and hold progress in ~10 steps, so SwiftUI is not redrawn 50×/s.
    /// Runs on the motion queue.
    private func shouldPublish(_ phase: CalibrationPhase) -> Bool {
        let key: String
        switch phase {
        case .waitingForMovement: key = "move"
        case .waitingForStillness: key = "still"
        case .holding(let p): key = "hold\(Int(p * 10))"
        case .wrongPose(let m): key = "wrong" + m
        case .finished: key = "done"
        }
        guard key != lastPublishedKey else { return false }
        lastPublishedKey = key
        return true
    }

    private func apply(_ events: [CalibrationEvent], phase: CalibrationPhase, step: Int) {
        self.phase = phase
        self.stepIndex = step
        let phoneReachable = WatchConnectivityService.shared.isPhoneReachable
        phoneIsShowingInstructions = phoneReachable
        for event in events {
            switch event {
            case .stepStarted(let p):
                pose = p
                if p != .armsDown { Haptics.nextInstruction() }
                if !phoneReachable { Speaker.shared.say(p.spokenInstruction) }
            case .holdStarted:
                Haptics.holdStarted()
            case .poseCaptured:
                Haptics.poseCaptured()
            case .wrongPose(let message):
                Haptics.wrongPose()
                if !phoneReachable { Speaker.shared.say(message) }
            case .finished(let profile):
                motion.stop()
                isRunning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Haptics.calibrationDone() }
                if !phoneReachable { Speaker.shared.say("Calibration complete.") }
                onFinish?(profile)
            }
        }
        // Mirror to the iPhone.
        let live = currentLiveState
        if CalibrationLiveState.isWorthSending(live, after: lastSentState),
           WatchConnectivityService.shared.sendLive(live) {
            lastSentState = live
        }
    }

    private var currentLiveState: CalibrationLiveState {
        var live = CalibrationLiveState(step: stepIndex, pose: pose, phase: phase)
        live.backgroundIssue = session?.backgroundIssue
        return live
    }

    /// Sends the current step again (the phone reconnected, or the background status changed).
    func resendToPhone() {
        guard isRunning else { return }
        phoneIsShowingInstructions = WatchConnectivityService.shared.isPhoneReachable
        let live = currentLiveState
        if WatchConnectivityService.shared.sendLive(live) { lastSentState = live }
    }
}
