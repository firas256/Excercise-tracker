import Foundation
import WatchKit

/// Drives the guided calibration: streams motion into `CalibrationEngine`, publishes the current
/// instruction/phase for the UI and plays a haptic for every state change.
final class CalibrationViewModel: ObservableObject {
    @Published private(set) var pose: CalibrationPose = .armsDown
    @Published private(set) var phase: CalibrationPhase = .waitingForStillness
    @Published private(set) var stepIndex = 0
    @Published private(set) var isRunning = false

    var onFinish: ((CalibrationProfile) -> Void)?

    private let motion: MotionService
    private var engine = CalibrationEngine()
    private var lastPublishedProgress = -1.0

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
        motion.queue.async {
            self.engine = engine
            let events = engine.start()
            let phase = engine.phase
            DispatchQueue.main.async { self.apply(events, phase: phase, step: engine.stepIndex) }
        }
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
        isRunning = false
    }

    /// Throttles hold-progress updates to ~10 steps so SwiftUI is not redrawn 50×/s.
    private func shouldPublish(_ phase: CalibrationPhase) -> Bool {
        if case .holding(let p) = phase {
            let bucket = (p * 10).rounded(.down) / 10
            if bucket != lastPublishedProgress {
                lastPublishedProgress = bucket
                return true
            }
            return false
        }
        if lastPublishedProgress != -1 {
            lastPublishedProgress = -1
            return true
        }
        return false
    }

    private func apply(_ events: [CalibrationEvent], phase: CalibrationPhase, step: Int) {
        self.phase = phase
        self.stepIndex = step
        for event in events {
            switch event {
            case .stepStarted(let p):
                pose = p
                if p != .armsDown { Haptics.nextInstruction() }
            case .holdStarted:
                Haptics.holdStarted()
            case .poseCaptured:
                Haptics.poseCaptured()
            case .wrongPose:
                Haptics.wrongPose()
            case .finished(let profile):
                motion.stop()
                isRunning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Haptics.calibrationDone() }
                onFinish?(profile)
            }
        }
    }
}
