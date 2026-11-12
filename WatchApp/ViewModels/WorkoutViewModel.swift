import Foundation

/// Live workout logic on the watch: motion → arm frame → `LiveSetTracker` → UI, haptics and
/// the list of completed sets.
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
        }
    }

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
        }
        motion.start { [weak self] sample in
            guard let self else { return }
            let events = self.tracker.ingest(profile.armSample(from: sample))
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { events.forEach(self.handle) }
        }
    }

    func stop() {
        motion.stop()
        if pendingSet != nil { confirmPendingSet(exercise: nil, reps: nil, weight: nil) }
        status = .waitingForSet
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
    }

    private func makeClassifier() -> ExerciseClassifying {
        BlendedExerciseClassifier(prototype: PrototypeExerciseClassifier(personalization: store.personalization), coreML: coreML)
    }

    private func handle(_ event: TrackerEvent) {
        switch event {
        case .setStarted:
            // Starting the next set auto-saves an unreviewed one.
            if pendingSet != nil { confirmPendingSet(exercise: nil, reps: nil, weight: nil) }
            status = .inSet
            repCount = 0
            liveCue = nil
            candidates = []
            restStartedAt = nil
            setStartWallClock = Date()
            Haptics.setStarted()
        case .repsUpdated(let count, let lastRep):
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
            pendingSet = PendingSet(completed: set, startDate: setStartWallClock,
                                    endDate: setStartWallClock.addingTimeInterval(duration))
            candidates = set.analysis.candidates
            repCount = set.analysis.repCount
            status = .reviewing
        case .setDiscarded:
            status = .waitingForSet
            repCount = 0
            liveCue = nil
        }
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
    }

    func discardPendingSet() {
        pendingSet = nil
        status = .waitingForSet
        repCount = 0
        liveCue = nil
    }
}
