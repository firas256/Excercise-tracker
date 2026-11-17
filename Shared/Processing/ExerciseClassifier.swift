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
    /// Examples needed before the user's sets may add a feature the built-in pattern leaves out on
    /// purpose (e.g. the grip of an exercise done with several grips). A few examples – which may be
    /// mislabelled – shouldn't create new rules.
    var examplesForNewFeatures = 8
    /// Penalise classes for being spread out (Gaussian normalisation). Off: a varied user class
    /// isn't punished for its variety.
    var widthPenalty = true
    /// The user's measured body: the built-in patterns are scaled to their arm length, and the
    /// swing radius is compared with their own forearm / arm length.
    var body: BodyProfile

    init(personalization: ClassifierPersonalization = ClassifierPersonalization(),
         candidates: [ExerciseType] = ExerciseType.allCases.filter { $0.isAutoDetectable },
         body: BodyProfile = .typical) {
        self.personalization = personalization
        self.candidates = candidates
        self.body = body
    }

    /// The built-in pattern fitted to this user's body.
    func bodyStats(for proto: ExercisePrototype) -> [MotionFeatures.Key: FeatureGaussian] {
        var stats = proto.stats
        // Distances scale with arm length (a shorter arm moves the weight fewer centimetres).
        for key in [MotionFeatures.Key.verticalAmplitude, .forearmAmplitude] {
            if var g = stats[key] {
                g.mean *= body.sizeScale
                g.sd *= body.sizeScale
                stats[key] = g
            }
        }
        switch ExercisePrototypes.pivot(proto.exercise) {
        case .elbow?: stats[.pivotRadius] = FeatureGaussian(mean: body.forearmLength * 100, sd: 8)
        case .shoulder?: stats[.pivotRadius] = FeatureGaussian(mean: body.armLength * 100 * 0.95, sd: 13)
        case nil: break
        }
        return stats
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
                let width = widthPenalty ? log(g.sd / ref) : 0
                logScore += ExercisePrototypes.weight(key) * (-0.5 * min(z * z, 25) - width)
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
        let base = bodyStats(for: proto)
        guard let examples = personalization.examples[proto.exercise], !examples.isEmpty else { return base }
        var out = base
        for key in MotionFeatures.Key.allCases {
            let xs = examples.compactMap { $0.value(key) }
            guard !xs.isEmpty else { continue }
            if base[key] == nil && xs.count < examplesForNewFeatures { continue }
            let prior = base[key] ?? FeatureGaussian(mean: SignalMath.mean(xs), sd: ExercisePrototypes.defaultSD(key))
            let k0 = base[key] == nil ? 0.5 : priorStrength
            let n = Double(xs.count)
            let mean = (k0 * prior.mean + xs.reduce(0, +)) / (k0 + n)
            let ss = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            let variance = (k0 * prior.sd * prior.sd + ss) / (k0 + n)
            out[key] = FeatureGaussian(mean: mean, sd: max(variance.squareRoot(), ExercisePrototypes.minimumSD(key)))
        }
        return out
    }
}
