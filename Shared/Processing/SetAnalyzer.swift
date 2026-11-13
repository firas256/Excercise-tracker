import Foundation

struct SetAnalysis {
    var detection: RepDetectionResult?
    var reps: [RepMetrics]
    var features: MotionFeatures?
    var candidates: [ExerciseCandidate]
    /// Locked exercise, or the best guess.
    var exercise: ExerciseType?
    var feedback: SetFeedback

    var repCount: Int { reps.count }
    var confidence: Double { candidates.first?.probability ?? 0 }

    static let empty = SetAnalysis(detection: nil, reps: [], features: nil, candidates: [], exercise: nil, feedback: .empty)
}

/// Runs the full pipeline on a buffer of arm-frame samples: reps → features → exercise → feedback.
struct SetAnalyzer {
    var classifier: ExerciseClassifying
    /// The user's measured body (from calibration): personal angles, grip range and arm length.
    var body: BodyProfile

    init(classifier: ExerciseClassifying? = nil, body: BodyProfile = .typical) {
        self.classifier = classifier ?? PrototypeExerciseClassifier(body: body)
        self.body = body
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
            candidates = GripModel.apply(classifier.classify(features, samples: samples), features: features, body: body)
        }
        let exercise = lockedExercise ?? candidates.first?.exercise
        let reps = FeedbackEngine.repMetrics(signals, detection: detection, exercise: exercise, body: body)
        let feedback = FeedbackEngine.setFeedback(reps, exercise: exercise, body: body)
        return SetAnalysis(detection: detection, reps: reps, features: features, candidates: candidates,
                           exercise: exercise, feedback: feedback)
    }
}
