import CoreML
import Foundation

/// Core ML exercise classifier.
///
/// The app ships `ExerciseActivityClassifier.mlpackage`, a small 1-D CNN trained on the Microsoft
/// Research RecoFit dataset (see ML/README.md). You can replace it with your own model trained in
/// Create ML (Activity Classifier) on the CSVs the iPhone app exports, as long as it keeps the name.
/// Inputs are matched by name to the arm-frame columns (`TrainingCSV.featureColumns`); the window
/// length comes from the input shape and the sample rate from the model's "sample_rate" metadata.
final class CoreMLExerciseClassifier: ExerciseClassifying {
    static let modelName = "ExerciseActivityClassifier"

    private let model: MLModel
    private let windowSize: Int
    private let modelRate: Double?
    private let inputColumns: [(name: String, column: Int)]
    private let stateInput: (name: String, shape: [NSNumber])?
    private let probabilityOutput: String
    /// Window predictions keyed by the window's first timestamp; a set's buffer only grows, so
    /// earlier windows never change while re-analysing it.
    private var cache: [Double: [ExerciseType: Double]] = [:]
    private var cacheSetStart: Double?
    /// Exercises the model was trained on (it says nothing about the others).
    private(set) var knownExercises: Set<ExerciseType> = []

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: Self.modelName, withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url) else { return nil }
        var columns: [(String, Int)] = []
        var window = 0
        var state: (String, [NSNumber])?
        for (name, description) in model.modelDescription.inputDescriptionsByName {
            if let index = TrainingCSV.featureColumns.firstIndex(of: name) {
                columns.append((name, index))
                if let first = description.multiArrayConstraint?.shape.first?.intValue {
                    window = max(window, first)
                }
            } else if name.lowercased().contains("state"), let shape = description.multiArrayConstraint?.shape {
                state = (name, shape)
            }
        }
        guard !columns.isEmpty, window > 1,
              let output = model.modelDescription.outputDescriptionsByName.first(where: { $0.value.type == .dictionary })?.key
        else { return nil }
        let metadata = model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String]
        self.model = model
        self.windowSize = window
        self.modelRate = metadata?["sample_rate"].flatMap(Double.init)
        self.inputColumns = columns
        self.stateInput = state
        self.probabilityOutput = output
        let labels = (model.modelDescription.classLabels as? [String]) ?? []
        self.knownExercises = Set(labels.compactMap(ExerciseType.init(rawValue:)))
    }

    func classify(_ features: MotionFeatures, samples: [ArmSample]) -> [ExerciseCandidate] {
        guard samples.count > 1, let first = samples.first, let last = samples.last, last.t > first.t else { return [] }
        if cacheSetStart != first.t {
            cache.removeAll()
            cacheSetStart = first.t
        }
        // Resample to the model's rate by averaging groups of samples (e.g. 50 Hz -> 25 Hz).
        let appRate = Double(samples.count - 1) / (last.t - first.t)
        let factor = max(1, Int(((modelRate.map { appRate / $0 }) ?? 1).rounded()))
        var rows: [[Double]] = []
        var times: [Double] = []
        rows.reserveCapacity(samples.count / factor)
        var i = 0
        while i + factor <= samples.count {
            var acc = [Double](repeating: 0, count: TrainingCSV.featureColumns.count)
            for k in i..<(i + factor) {
                let v = TrainingCSV.values(of: samples[k])
                for c in 0..<acc.count { acc[c] += v[c] }
            }
            for c in 0..<acc.count { acc[c] /= Double(factor) }
            let gn = (acc[0] * acc[0] + acc[1] * acc[1] + acc[2] * acc[2]).squareRoot()
            if gn > 1e-6 { for c in 0..<3 { acc[c] /= gn } }
            rows.append(acc)
            times.append(samples[i].t)
            i += factor
        }
        guard rows.count >= windowSize else { return [] }

        var sums: [ExerciseType: Double] = [:]
        var windows = 0
        var start = 0
        let hop = max(1, windowSize / 2)
        while start + windowSize <= rows.count {
            let key = times[start]
            let probabilities = cache[key] ?? predict(rows: rows[start..<(start + windowSize)])
            if let probabilities {
                cache[key] = probabilities
                for (label, p) in probabilities { sums[label, default: 0] += p }
                windows += 1
            }
            start += hop
        }
        guard windows > 0 else { return [] }
        // Probabilities of "other" (not a tracked exercise) are dropped, so these may sum to < 1.
        return sums.map { ExerciseCandidate(exercise: $0.key, probability: $0.value / Double(windows)) }
            .sorted { $0.probability > $1.probability }
    }

    private func predict(rows: ArraySlice<[Double]>) -> [ExerciseType: Double]? {
        do {
            var inputs: [String: Any] = [:]
            for (name, column) in inputColumns {
                let array = try MLMultiArray(shape: [NSNumber(value: windowSize)], dataType: .float32)
                for (i, row) in rows.enumerated() { array[i] = NSNumber(value: row[column]) }
                inputs[name] = MLFeatureValue(multiArray: array)
            }
            if let stateInput {
                let state = try MLMultiArray(shape: stateInput.shape, dataType: .double)
                for i in 0..<state.count { state[i] = 0 }
                inputs[stateInput.name] = MLFeatureValue(multiArray: state)
            }
            let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
            let output = try model.prediction(from: provider)
            guard let dict = output.featureValue(for: probabilityOutput)?.dictionaryValue else { return nil }
            var result: [ExerciseType: Double] = [:]
            for (key, value) in dict {
                if let label = key as? String, let exercise = ExerciseType(rawValue: label) {
                    result[exercise] = value.doubleValue
                }
            }
            knownExercises.formUnion(result.keys)  // in case the model doesn't list its labels
            return result
        } catch {
            return nil
        }
    }
}

/// Combines the built-in prototype classifier (which learns from your corrections) with the
/// Core ML model (which learned from many people).
struct BlendedExerciseClassifier: ExerciseClassifying {
    var prototype: PrototypeExerciseClassifier
    var coreML: CoreMLExerciseClassifier?
    /// Weight of the Core ML model when it is available.
    var coreMLWeight = 0.65

    func classify(_ features: MotionFeatures, samples: [ArmSample]) -> [ExerciseCandidate] {
        let base = prototype.classify(features, samples: samples)
        guard let coreML else { return base }
        let ml = coreML.classify(features, samples: samples)
        guard !ml.isEmpty else { return base }
        // Your own confirmed sets shift trust towards the personalised classifier.
        let learned = Double(prototype.personalization.totalExamples)
        let w = max(0.3, coreMLWeight * 20 / (20 + learned))
        return ClassifierBlend.combine(prototype: base, model: ml, modelKnows: coreML.knownExercises, modelWeight: w)
    }
}
