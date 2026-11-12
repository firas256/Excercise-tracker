import Foundation

/// Anything that can guess the exercise for a set. The watch uses the built-in
/// `PrototypeExerciseClassifier`, optionally blended with a Core ML model you train yourself.
protocol ExerciseClassifying {
    /// Returns candidates sorted by probability (highest first).
    func classify(_ features: MotionFeatures, samples: [ArmSample]) -> [ExerciseCandidate]
}

/// Saved user corrections / confirmations used to personalise the classifier.
struct ClassifierPersonalization: Codable, Equatable, Sendable {
    var examples: [ExerciseType: [MotionFeatures]] = [:]
    static let maxExamplesPerExercise = 30

    var totalExamples: Int { examples.values.reduce(0) { $0 + $1.count } }

    mutating func add(_ features: MotionFeatures, label: ExerciseType) {
        var list = examples[label] ?? []
        list.append(features)
        if list.count > Self.maxExamplesPerExercise { list.removeFirst(list.count - Self.maxExamplesPerExercise) }
        examples[label] = list
    }
}

/// Gaussian "naive Bayes" classifier over orientation-independent motion features.
///
/// It starts from hand-made biomechanical prototypes (see `ExercisePrototypes`) and performs a
/// Bayesian update of each exercise's feature distribution every time you confirm or correct a set,
/// so it gradually adapts to *your* form without a separate data-collection session.
struct PrototypeExerciseClassifier: ExerciseClassifying {
    var personalization: ClassifierPersonalization
    /// Restrict guesses to these exercises (defaults to all auto-detectable ones).
    var candidates: [ExerciseType]
    /// Strength (in pseudo-examples) of the built-in prototype when blending with user data.
    var priorStrength: Double = 2

    init(personalization: ClassifierPersonalization = ClassifierPersonalization(),
         candidates: [ExerciseType] = ExerciseType.allCases.filter { $0.isAutoDetectable }) {
        self.personalization = personalization
        self.candidates = candidates
    }

    func classify(_ features: MotionFeatures, samples: [ArmSample] = []) -> [ExerciseCandidate] {
        var scores: [(ExerciseType, Double)] = []
        for proto in ExercisePrototypes.all where candidates.contains(proto.exercise) {
            let model = personalizedStats(for: proto)
            var logScore = log(max(proto.prior, 1e-3))
            // Exercises you do often get a mild prior boost.
            let userCount = Double(personalization.examples[proto.exercise]?.count ?? 0)
            logScore += 0.15 * log(1 + userCount)
            for key in MotionFeatures.Key.allCases {
                guard let x = features.value(key), let g = model[key] else { continue }
                let z = (x - g.mean) / g.sd
                let ref = ExercisePrototypes.defaultSD(key)
                // Cap the penalty so a single odd feature cannot veto an exercise.
                logScore += ExercisePrototypes.weight(key) * (-0.5 * min(z * z, 25) - log(g.sd / ref))
            }
            scores.append((proto.exercise, logScore))
        }
        guard let maxScore = scores.map({ $0.1 }).max() else { return [] }
        let exps = scores.map { ($0.0, exp($0.1 - maxScore)) }
        let total = exps.reduce(0) { $0 + $1.1 }
        return exps
            .map { ExerciseCandidate(exercise: $0.0, probability: $0.1 / total) }
            .sorted { $0.probability > $1.probability }
    }

    /// Prototype statistics blended with the user's own examples (conjugate-style update).
    func personalizedStats(for proto: ExercisePrototype) -> [MotionFeatures.Key: FeatureGaussian] {
        guard let examples = personalization.examples[proto.exercise], !examples.isEmpty else { return proto.stats }
        var out = proto.stats
        for key in MotionFeatures.Key.allCases {
            let xs = examples.compactMap { $0.value(key) }
            guard !xs.isEmpty else { continue }
            let prior = proto.stats[key] ?? FeatureGaussian(mean: SignalMath.mean(xs), sd: ExercisePrototypes.defaultSD(key))
            let k0 = proto.stats[key] == nil ? 0.5 : priorStrength
            let n = Double(xs.count)
            let mean = (k0 * prior.mean + xs.reduce(0, +)) / (k0 + n)
            let ss = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            let variance = (k0 * prior.sd * prior.sd + ss) / (k0 + n)
            out[key] = FeatureGaussian(mean: mean, sd: max(variance.squareRoot(), ExercisePrototypes.minimumSD(key)))
        }
        return out
    }
}
