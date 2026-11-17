import Foundation
import WatchConnectivity

/// Receives workouts, calibration info and training recordings from the watch.
final class PhoneConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isSupported = WCSession.isSupported()
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    /// The session has activated, so isPaired / isWatchAppInstalled are known.
    @Published private(set) var isActivated = false
    /// Live calibration running on the watch (nil when none). Drives the full-screen guide.
    @Published var liveCalibration: CalibrationLiveState?
    /// Live workout running on the watch (nil when none). Drives the full-screen workout screen.
    @Published var liveWorkout: LiveWorkoutState?
    /// The user tucked the live workout screen away (it comes back from the dashboard banner).
    @Published var liveWorkoutMinimized = false
    /// Recent arm-motion frames (last ~10 s) and when the latest batch arrived.
    @Published private(set) var frames: [MotionFrame] = []
    @Published private(set) var lastFrameArrival: Date?
    @Published private(set) var lastLiveUpdate: Date?
    private var demoTimer: Timer?
    private var staleTimer: Timer?
    private var demoFrames: [MotionFrame] = []
    private var demoIndex = 0
    private var demoOffset = 0.0

    private let store: WorkoutStore

    init(store: WorkoutStore) {
        self.store = store
        super.init()
        activate()
        // `-demoCalibration YES` launch argument: show the calibration guide (Simulator / screenshots).
        if UserDefaults.standard.bool(forKey: "demoCalibration") {
            liveCalibration = CalibrationLiveState(step: 1, pose: .armForward, phase: .holding(0.6))
        }
        // `-demoLiveWorkout live|review`: show the live workout screen with simulated curls.
        if let demo = UserDefaults.standard.string(forKey: "demoLiveWorkout") {
            startDemo(review: demo == "review")
        }
        // The watch sends a heartbeat every ~5 s; if it has been silent for 2 minutes the
        // workout ended out of range – stop showing it (it comes back if the watch reappears).
        staleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.demoTimer == nil, self.liveWorkout != nil,
                  Date().timeIntervalSince(self.lastLiveUpdate ?? .distantPast) > 120 else { return }
            self.liveWorkout = nil
            self.frames = []
        }
    }

    /// Asks the watch for the current workout state (after the phone app comes back to the foreground).
    func refreshLiveWorkout() {
        send(.requestState)
    }

    /// Sends a button press to the watch: live when it's reachable, otherwise (or if that fails)
    /// queued for delivery, time-stamped so the watch can drop it if it arrives too late to mean
    /// the same thing (see `WatchCommand.maxQueuedAge`).
    func send(_ command: WatchCommand) {
        if demoTimer != nil { applyDemo(command); return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = PayloadCoding.encode(command) else { return }
        let payload: [String: Any] = [SyncKeys.command: data, SyncKeys.sentAt: Date().timeIntervalSince1970]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                if command != .requestState { WCSession.default.transferUserInfo(payload) }
            }
        } else if command != .requestState {
            WCSession.default.transferUserInfo(payload)
        }
    }

    /// Newest `sentAt` accepted per live key, so a late queued update never replaces a newer one.
    private var latestAccepted: [String: Double] = [:]

    /// Live calibration / workout updates, from a live message or a queued transfer. Main thread.
    private func handleLive(_ payload: [String: Any], queued: Bool) {
        let stamp = payload[SyncKeys.sentAt] as? Double
        func isCurrent(_ key: String) -> Bool {
            guard let stamp else { return true }
            if stamp < latestAccepted[key] ?? 0 { return false }
            // A queued update that took ages is history (e.g. the app was closed meanwhile).
            if queued, Date().timeIntervalSince1970 - stamp > 60 { return false }
            latestAccepted[key] = stamp
            return true
        }
        if let data = payload[SyncKeys.liveWorkout] as? Data,
           let state = PayloadCoding.decode(LiveWorkoutState.self, from: data) {
            if isCurrent(SyncKeys.liveWorkout) { receive(state) }
            return
        }
        if let data = payload[SyncKeys.motionFrames] as? Data,
           let frames = PayloadCoding.decode([MotionFrame].self, from: data) {
            receive(frames)
            return
        }
        if let data = payload[SyncKeys.calibrationLive] as? Data,
           let state = PayloadCoding.decode(CalibrationLiveState.self, from: data),
           isCurrent(SyncKeys.calibrationLive) {
            receive(state)
        }
    }

    private func receive(_ state: CalibrationLiveState) {
        switch state.status {
        case .cancelled:
            liveCalibration = nil
        case .finished:
            liveCalibration = state
            // Leave "Calibrated!" up for a moment, then get out of the way.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.liveCalibration?.status == .finished { self.liveCalibration = nil }
            }
        default:
            liveCalibration = state
        }
    }

    private func receive(_ state: LiveWorkoutState) {
        if liveWorkout == nil || liveWorkout?.status == .ended { liveWorkoutMinimized = false }
        liveWorkout = state
        lastLiveUpdate = Date()
        if state.status == .ended {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.liveWorkout?.status == .ended {
                    self.liveWorkout = nil
                    self.frames = []
                }
            }
        }
    }

    private func receive(_ newFrames: [MotionFrame]) {
        guard let last = newFrames.last else { return }
        if let previous = frames.last, last.t < previous.t - 1 { frames = [] }  // new session clock
        frames.append(contentsOf: newFrames)
        frames.removeAll { $0.t < last.t - 10 }
        lastFrameArrival = Date()
        lastLiveUpdate = Date()
    }

    // MARK: Demo (Simulator / screenshots)

    private func startDemo(review: Bool) {
        var o = SyntheticMotion.Options()
        o.reps = 30
        o.stillLead = 1
        guard let samples = SyntheticMotion.generate(.bicepCurl, options: o) else { return }
        let demoFrames = MotionFrameBuilder.frames(from: samples, outputRate: 15)
        var state = LiveWorkoutState.idle
        state.status = review ? .reviewing : .inSet
        state.repCount = 6
        state.liveCue = "Good rep"
        state.candidates = [ExerciseCandidate(exercise: .bicepCurl, probability: 0.82),
                            ExerciseCandidate(exercise: .hammerCurl, probability: 0.09),
                            ExerciseCandidate(exercise: .lateralRaise, probability: 0.04)]
        state.completedSets = 2
        state.workoutStartedAt = Date().addingTimeInterval(-8 * 60)
        state.heartRate = 124
        state.activeEnergy = 46
        if review {
            let analysis = SetAnalyzer().analyze(Array(samples.prefix(1100)), lockedExercise: .bicepCurl)
            state.pendingSet = PendingSetSummary(id: UUID(), exercise: .bicepCurl, candidates: state.candidates,
                                                 repCount: analysis.repCount, feedback: analysis.feedback,
                                                 weight: 12.5, weightUnit: "kg")
        }
        liveWorkout = state
        lastLiveUpdate = Date()
        self.demoFrames = demoFrames
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.pumpDemoFrames() }
        }
    }

    private func pumpDemoFrames() {
        guard !demoFrames.isEmpty else { return }
        let start = demoFrames[0].t
        var batch: [MotionFrame] = []
        for _ in 0..<3 {
            var f = demoFrames[demoIndex]
            f.t = f.t - start + demoOffset
            batch.append(f)
            demoIndex += 1
            if demoIndex == demoFrames.count {
                demoIndex = 0
                demoOffset += (demoFrames.last?.t ?? 0) - start + 1.0 / 15
            }
        }
        receive(batch)
    }

    private func applyDemo(_ command: WatchCommand) {
        guard var state = liveWorkout else { return }
        switch command {
        case .lockExercise(let e): state.lockedExercise = e
        case .savePendingSet, .discardPendingSet:
            state.pendingSet = nil
            state.status = .waitingForSet
            state.restStartedAt = Date()
        case .endWorkout:
            state.status = .ended
            demoTimer?.invalidate()
            demoTimer = nil
        case .endSet:
            state.status = .reviewing
        default: break
        }
        receive(state)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    private func refreshState(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        let activated = session.activationState == .activated
        DispatchQueue.main.async {
            self.isPaired = paired
            self.isWatchAppInstalled = installed
            self.isReachable = reachable
            self.isActivated = activated
        }
    }

    private func handle(context: [String: Any]) {
        if let data = context[SyncKeys.calibration] as? Data,
           let summary = PayloadCoding.decode(CalibrationSummary.self, from: data) {
            DispatchQueue.main.async { self.store.setCalibration(summary) }
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refreshState(session)
        handle(context: session.receivedApplicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after switching to a different watch.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) { refreshState(session) }

    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshState(session)
        if session.isReachable {
            DispatchQueue.main.async { self.refreshLiveWorkout() }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[SyncKeys.workout] as? Data,
           let workout = PayloadCoding.decode(WorkoutRecord.self, from: data) {
            DispatchQueue.main.async { self.store.add(workout) }
            return
        }
        // Live updates the watch queued while it couldn't message the phone directly.
        DispatchQueue.main.async { self.handleLive(userInfo, queued: true) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.handleLive(message, queued: false) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(context: applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so move it synchronously.
        let label = file.metadata?[SyncKeys.trainingLabel] as? String ?? "unlabeled"
        let setID = file.metadata?[SyncKeys.trainingSetID] as? String ?? UUID().uuidString
        store.storeTrainingFile(at: file.fileURL, label: label, setID: setID)
    }
}
