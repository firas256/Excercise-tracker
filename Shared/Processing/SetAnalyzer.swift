import Foundation

struct SetAnalysis {
    var detection: RepDetectionResult?
    var reps: [RepMetrics]
    var features: MotionFeatures?
    var candidates: [ExerciseCandidate]
    /// Locked exercise, or the best guess.
    var exercise: ExerciseType?
    var feedback: SetFeedback
    /// Reps with less than half the required range: detected, but not counted.
    var tooShortReps: [RepMetrics] = []
    /// The range a full rep should have (in the reps' unit); reps under half of it don't count.
    var requiredRange: Double?

    var repCount: Int { reps.count }
    var confidence: Double { candidates.first?.probability ?? 0 }

    static let empty = SetAnalysis(detection: nil, reps: [], features: nil, candidates: [], exercise: nil, feedback: .empty)
}

/// Runs the full pipeline on a buffer of arm-frame samples: reps → features → exercise → feedback.
struct SetAnalyzer {
    var classifier: ExerciseClassifying
    /// The user's measured body (from calibration): personal angles, grip range and arm length.
    var body: BodyProfile
    /// The user's confirmed sets: grips they use count as normal for those exercises.
    var personalization: ClassifierPersonalization

    init(classifier: ExerciseClassifying? = nil, body: BodyProfile = .typical,
         personalization: ClassifierPersonalization = ClassifierPersonalization()) {
        self.classifier = classifier ?? PrototypeExerciseClassifier(personalization: personalization, body: body)
        self.body = body
        self.personalization = personalization
    }

    func analyze(_ samples: [ArmSample], lockedExercise: ExerciseType? = nil) -> SetAnalysis {
        let signals = MotionSignals(samples: samples)
        let sensitivity = lockedExercise?.trackingQuality == .limited ? 0.4 : 1.0
        guard let detection = RepDetector.detect(signals, preferred: lockedExercise?.preferredSignal, sensitivity: sensitivity),
              !detection.segments.isEmpty else {
            return SetAnalysis(detection: nil, reps: [], features: nil, candidates: [], exercise: lockedExercise, feedback: .empty)
        }
        let features = FeatureExtractor.extract(signals, detection: detection)
        var candidates: [ExerciseCandidate] = []
        if lockedExercise == nil, let features, detection.segments.count >= 2 {
            // The grip rules out exercises whatever suggested them (including the Core ML model).
            candidates = GripModel.apply(classifier.classify(features, samples: samples), features: features, body: body,
                                         personal: personalization)
        }
        let exercise = lockedExercise ?? candidates.first?.exercise
        let allReps = FeedbackEngine.repMetrics(signals, detection: detection, exercise: exercise, body: body)
        // Only trust the exercise's full range when it's certain, so a wrong guess can't discard good reps.
        let certain = lockedExercise != nil || (candidates.first?.probability ?? 0) >= 0.6
        let split = FeedbackEngine.separateTooShort(allReps, exercise: exercise, exerciseIsCertain: certain,
                                                    signal: detection.signal, body: body)
        let skipped = FeedbackEngine.skippedAttempts(signals, detection: detection, counted: split.counted,
                                                     exercise: exercise, exerciseIsCertain: certain, body: body)
        let tooShort = (split.tooShort + skipped).sorted { $0.startTime < $1.startTime }
        let feedback = FeedbackEngine.setFeedback(split.counted, exercise: exercise, body: body,
                                                  notCounted: tooShort.count, requiredRange: split.required)
        return SetAnalysis(detection: detection, reps: split.counted, features: features, candidates: candidates,
                           exercise: exercise, feedback: feedback, tooShortReps: tooShort,
                           requiredRange: split.required)
    }
}
