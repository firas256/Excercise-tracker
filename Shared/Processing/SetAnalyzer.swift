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

    init(classifier: ExerciseClassifying = PrototypeExerciseClassifier()) {
        self.classifier = classifier
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
            candidates = classifier.classify(features, samples: samples)
        }
        let exercise = lockedExercise ?? candidates.first?.exercise
        let reps = FeedbackEngine.repMetrics(signals, detection: detection, exercise: exercise)
        let feedback = FeedbackEngine.setFeedback(reps, exercise: exercise)
        return SetAnalysis(detection: detection, reps: reps, features: features, candidates: candidates,
                           exercise: exercise, feedback: feedback)
    }
}
