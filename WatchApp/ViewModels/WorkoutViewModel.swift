import Foundation

/// Live workout logic on the watch: motion → arm frame → `LiveSetTracker` → UI, haptics and
/// the list of completed sets. Also mirrors everything to the iPhone (state + arm motion) and
/// accepts the iPhone's buttons, so the workout can be followed and controlled from the phone.
final class WorkoutViewModel: ObservableObject {
    enum Status: Equatable {
        case waitingForSet
        case inSet
        case reviewing
    }

    /// A finished set waiting for the user to confirm or correct it.
    struct PendingSet: Identifiable {
        let id = UUID()
        var completed: CompletedSet
        var startDate: Date
        var endDate: Date
    }

    @Published private(set) var status: Status = .waitingForSet
    @Published private(set) var repCount = 0
    @Published private(set) var liveCue: String?
    @Published private(set) var lastRepFlagged = false
    @Published private(set) var candidates: [ExerciseCandidate] = []
    @Published private(set) var completedSets: [SetRecord] = []
    @Published private(set) var restStartedAt: Date?
    @Published var pendingSet: PendingSet?
    @Published var lockedExercise: ExerciseType? {
        didSet {
            let value = lockedExercise
            motion.queue.async { self.tracker.lockedExercise = value }
            publishLiveState()
        }
    }

    /// Heart rate / calories / start time for the phone.
    weak var session: WorkoutSessionService?
    /// The phone asked to end the workout.
    var onEndWorkoutRequested: (() -> Void)?
    private let frameBuilder = MotionFrameBuilder(outputRate: 15)
    private var frameBatch: [MotionFrame] = []        // motion queue only
    private var lastSentLiveState: LiveWorkoutState?
    private var liveTimer: Timer?
    private var lastLiveSentAt = Date.distantPast
    private var workoutActive = false

    let store: WatchStore
    private let motion: MotionService
    private let tracker = LiveSetTracker()
    private let coreML = CoreMLExerciseClassifier()
    private var setStartWallClock = Date()

    var hasCoreMLModel: Bool { coreML != nil }

    init(store: WatchStore, motion: MotionService = .shared) {
        self.store = store
        self.motion = motion
    }

    var currentGuess: ExerciseType? { lockedExercise ?? candidates.first?.exercise }

    func begin(profile: CalibrationProfile) {
        completedSets = []
        candidates = []
        repCount = 0
        status = .waitingForSet
        restStartedAt = nil
        pendingSet = nil
        var configuration = LiveSetTracker.Configuration()
        configuration.restTimeout = max(3, WatchSettings.restTimeout)
        let classifier = makeClassifier()
        let locked = lockedExercise
        motion.queue.async {
            self.tracker.configuration = configuration
            self.tracker.analyzer = SetAnalyzer(classifier: classifier)
            self.tracker.lockedExercise = locked
            self.tracker.cancelSet()
            self.frameBuilder.reset()
            self.frameBatch.removeAll()
        }
        motion.simulationScenario = .workout
        motion.start { [weak self] sample in
            guard let self else { return }
            let arm = profile.armSample(from: sample)
            let events = self.tracker.ingest(arm)
            // Stream the arm motion to the phone (15 frames/s, sent in small batches).
            if let frame = self.frameBuilder.add(arm) {
                self.frameBatch.append(frame)
                if self.frameBatch.count >= 3 {
                    WatchConnectivityService.shared.sendFrames(self.frameBatch)
                    self.frameBatch.removeAll()
                }
            }
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { events.forEach(self.handle) }
        }
        workoutActive = true
        lastSentLiveState = nil
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.publishLiveState()
        }
        publishLiveState()
    }

    func stop() {
        motion.stop()
        // A set still in progress (workout ended right after the last rep) is kept, not dropped.
        let events = motion.queue.sync { tracker.finishSet() }
        events.forEach(handle)
        if pendingSet != nil { confirmPendingSet(exercise: nil, reps: nil, weight: nil) }
        status = .waitingForSet
        workoutActive = false
        liveTimer?.invalidate()
        liveTimer = nil
        var ended = makeLiveState()
        ended.status = .ended
        WatchConnectivityService.shared.sendLiveWorkout(ended)
        lastSentLiveState = ended
    }

    func endSetNow() {
        motion.queue.async {
            let events = self.tracker.finishSet()
            DispatchQueue.main.async { events.forEach(self.handle) }
        }
    }

    func cancelCurrentSet() {
        motion.queue.async { self.tracker.cancelSet() }
        status = .waitingForSet
        repCount = 0
        liveCue = nil
        publishLiveState()
    }

    // MARK: iPhone link

    /// A button pressed on the iPhone.
    func handle(_ command: WatchCommand) {
        switch command {
        case .lockExercise(let exercise):
            lockedExercise = exercise
        case .endSet:
            endSetNow()
        case .discardSet:
            cancelCurrentSet()
        case .savePendingSet(let id, let exercise, let reps, let weight):
            if pendingSet?.id == id { confirmPendingSet(exercise: exercise, reps: reps, weight: weight) }
        case .discardPendingSet(let id):
            if pendingSet?.id == id { discardPendingSet() }
        case .endWorkout:
            onEndWorkoutRequested?()
        case .requestState:
            lastSentLiveState = nil
            publishLiveState()
        }
    }

    private func makeLiveState() -> LiveWorkoutState {
        var state = LiveWorkoutState.idle
        switch status {
        case .waitingForSet: state.status = .waitingForSet
        case .inSet: state.status = .inSet
        case .reviewing: state.status = .reviewing
        }
        state.repCount = repCount
        state.liveCue = liveCue
        state.lastRepFlagged = lastRepFlagged
        state.candidates = Array(candidates.prefix(3))
        state.lockedExercise = lockedExercise
        state.completedSets = completedSets.count
        state.restStartedAt = restStartedAt
        state.workoutStartedAt = session?.startDate
        state.heartRate = session?.heartRate
        state.activeEnergy = session?.activeEnergy ?? 0
        state.backgroundIssue = session?.backgroundIssue
        if let pending = pendingSet {
            let analysis = pending.completed.analysis
            state.pendingSet = PendingSetSummary(
                id: pending.id,
                exercise: analysis.exercise,
                candidates: Array(analysis.candidates.prefix(5)),
                repCount: analysis.repCount,
                feedback: analysis.feedback,
                weight: analysis.exercise.flatMap { store.lastWeight(for: $0) },
                weightUnit: WatchSettings.weightUnit
            )
        }
        return state
    }

    /// Sends the workout state to the phone when it changed, plus a heartbeat every few seconds
    /// so the phone knows the watch is still there (and catches up after reconnecting).
    func publishLiveState() {
        guard workoutActive else { return }
        let state = makeLiveState()
        guard state != lastSentLiveState || Date().timeIntervalSince(lastLiveSentAt) > 5 else { return }
        if WatchConnectivityService.shared.sendLiveWorkout(state) {
            lastSentLiveState = state
            lastLiveSentAt = Date()
        }
    }

    private func makeClassifier() -> ExerciseClassifying {
        BlendedExerciseClassifier(prototype: PrototypeExerciseClassifier(personalization: store.personalization), coreML: coreML)
    }

    private func handle(_ event: TrackerEvent) {
        switch event {
        case .setStarted:
            // Movement started. This may still be a false start (e.g. lowering the arm), so the
            // rest timer, an open set summary and haptics are only touched once reps are detected.
            if pendingSet == nil {
                status = .inSet
                repCount = 0
                liveCue = nil
                candidates = []
            }
            setStartWallClock = Date()
        case .repsUpdated(let count, let lastRep):
            if pendingSet != nil {
                // A new set really started: auto-save the unreviewed one.
                confirmPendingSet(exercise: nil, reps: nil, weight: nil)
                status = .inSet
                candidates = []
                repCount = 0
            }
            restStartedAt = nil
            let increased = count > repCount
            repCount = count
            if let rep = lastRep {
                liveCue = FeedbackEngine.liveCue(for: rep)
                let flagged = rep.issues.contains { $0 != .slowingDown }
                lastRepFlagged = flagged
                if increased {
                    if flagged { Haptics.flaggedRep() } else if WatchSettings.hapticEveryRep { Haptics.goodRep() }
                }
            }
        case .exerciseGuess(let c):
            candidates = c
        case .setCompleted(let set):
            Haptics.setFinished()
            let duration = set.endTime - set.startTime
            if pendingSet != nil { confirmPendingSet(exercise: nil, reps: nil, weight: nil) }
            pendingSet = PendingSet(completed: set, startDate: setStartWallClock,
                                    endDate: setStartWallClock.addingTimeInterval(duration))
            candidates = set.analysis.candidates
            repCount = set.analysis.repCount
            status = .reviewing
        case .setDiscarded:
            if pendingSet == nil {
                status = .waitingForSet
                repCount = 0
                liveCue = nil
            }
        }
        publishLiveState()
    }

    /// Saves the pending set. nil arguments keep the detected values.
    func confirmPendingSet(exercise: ExerciseType?, reps: Int?, weight: Double?) {
        guard let pending = pendingSet else { return }
        let analysis = pending.completed.analysis
        let detected = lockedExercise == nil ? analysis.candidates.first?.exercise : nil
        let finalExercise = exercise ?? analysis.exercise ?? .bicepCurl
        let corrected = detected != nil && detected != finalExercise
        let record = SetRecord(
            id: UUID(),
            exercise: finalExercise,
            detectedExercise: detected,
            detectionConfidence: analysis.confidence,
            alternatives: Array(analysis.candidates.prefix(3)),
            userCorrectedExercise: corrected,
            repCount: reps ?? analysis.repCount,
            detectedRepCount: analysis.repCount,
            reps: analysis.reps,
            feedback: analysis.feedback,
            signal: analysis.detection?.signal ?? finalExercise.preferredSignal,
            weight: weight,
            weightUnit: WatchSettings.weightUnit,
            startDate: pending.startDate,
            endDate: pending.endDate,
            features: analysis.features
        )
        completedSets.append(record)
        store.setLastWeight(weight, for: finalExercise)

        // Every confirmed set teaches the classifier a little more about your form.
        if let features = analysis.features, finalExercise.isAutoDetectable {
            store.learn(features, label: finalExercise)
            let classifier = makeClassifier()
            motion.queue.async { self.tracker.analyzer = SetAnalyzer(classifier: classifier) }
        }
        if WatchSettings.recordTrainingData {
            WatchConnectivityService.shared.sendTrainingRecording(samples: pending.completed.samples,
                                                                  label: finalExercise, setID: record.id)
        }
        pendingSet = nil
        status = .waitingForSet
        restStartedAt = Date()
        liveCue = nil
        publishLiveState()
    }

    func discardPendingSet() {
        pendingSet = nil
        status = .waitingForSet
        repCount = 0
        liveCue = nil
        publishLiveState()
    }
}
