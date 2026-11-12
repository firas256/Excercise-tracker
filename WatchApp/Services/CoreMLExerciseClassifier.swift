import CoreML
import Foundation

/// Optional Core ML exercise classifier.
///
/// Train a model with Create ML's *Activity Classifier* template on the CSV recordings the iPhone
/// app exports (see ML/README.md), name it `ExerciseActivityClassifier.mlmodel` and add it to the
/// Watch App target. If present, it is used automatically and blended with the built-in classifier.
final class CoreMLExerciseClassifier: ExerciseClassifying {
    static let modelName = "ExerciseActivityClassifier"

    private let model: MLModel
    private let windowSize: Int
    private let inputColumns: [(name: String, column: Int)]
    private let stateInput: (name: String, shape: [NSNumber])?
    private let probabilityOutput: String

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
        self.model = model
        self.windowSize = window
        self.inputColumns = columns
        self.stateInput = state
        self.probabilityOutput = output
    }

    func classify(_ features: MotionFeatures, samples: [ArmSample]) -> [ExerciseCandidate] {
        guard samples.count >= windowSize else { return [] }
        let rows = samples.map { TrainingCSV.values(of: $0) }
        var sums: [ExerciseType: Double] = [:]
        var windows = 0
        var start = 0
        while start + windowSize <= rows.count {
            if let probabilities = predict(rows: rows[start..<(start + windowSize)]) {
                for (label, p) in probabilities { sums[label, default: 0] += p }
                windows += 1
            }
            start += max(1, windowSize / 2)
        }
        guard windows > 0 else { return [] }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [] }
        return sums.map { ExerciseCandidate(exercise: $0.key, probability: $0.value / total) }
            .sorted { $0.probability > $1.probability }
    }

    private func predict(rows: ArraySlice<[Double]>) -> [ExerciseType: Double]? {
        do {
            var inputs: [String: Any] = [:]
            for (name, column) in inputColumns {
                let array = try MLMultiArray(shape: [NSNumber(value: windowSize)], dataType: .double)
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
            return result
        } catch {
            return nil
        }
    }
}

/// Combines the built-in prototype classifier with an optional Core ML model.
struct BlendedExerciseClassifier: ExerciseClassifying {
    var prototype: PrototypeExerciseClassifier
    var coreML: CoreMLExerciseClassifier?
    /// Weight of the Core ML model when it is available.
    var coreMLWeight = 0.6

    func classify(_ features: MotionFeatures, samples: [ArmSample]) -> [ExerciseCandidate] {
        let base = prototype.classify(features, samples: samples)
        guard let coreML else { return base }
        let ml = coreML.classify(features, samples: samples)
        guard !ml.isEmpty else { return base }
        var combined: [ExerciseType: Double] = [:]
        for c in base { combined[c.exercise, default: 0] += (1 - coreMLWeight) * c.probability }
        for c in ml { combined[c.exercise, default: 0] += coreMLWeight * c.probability }
        let total = combined.values.reduce(0, +)
        return combined.map { ExerciseCandidate(exercise: $0.key, probability: $0.value / max(total, 1e-9)) }
            .sorted { $0.probability > $1.probability }
    }
}
