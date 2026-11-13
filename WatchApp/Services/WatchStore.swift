import Foundation

/// Small persistent store on the watch: calibration, what the classifier learned, last weights.
final class WatchStore {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let calibration = "calibrationProfile"
        static let personalization = "classifierPersonalization"
        static let lastWeights = "lastWeights"
    }

    var calibration: CalibrationProfile? {
        get { load(CalibrationProfile.self, key: Key.calibration) }
        set { save(newValue, key: Key.calibration) }
    }

    var personalization: ClassifierPersonalization {
        get { load(ClassifierPersonalization.self, key: Key.personalization) ?? ClassifierPersonalization() }
        set { save(newValue, key: Key.personalization) }
    }

    func learn(_ features: MotionFeatures, label: ExerciseType) {
        var p = personalization
        p.add(features, label: label)
        personalization = p
    }

    func resetLearning() {
        defaults.removeObject(forKey: Key.personalization)
    }

    func lastWeight(for exercise: ExerciseType) -> Double? {
        let all = defaults.dictionary(forKey: Key.lastWeights) as? [String: Double]
        return all?[exercise.rawValue]
    }

    func setLastWeight(_ weight: Double?, for exercise: ExerciseType) {
        var all = (defaults.dictionary(forKey: Key.lastWeights) as? [String: Double]) ?? [:]
        all[exercise.rawValue] = weight
        defaults.set(all, forKey: Key.lastWeights)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return PayloadCoding.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = PayloadCoding.encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// User-adjustable settings (also bound with @AppStorage in the settings screen).
enum WatchSettings {
    static let restTimeoutKey = "restTimeout"
    static let hapticEveryRepKey = "hapticEveryRep"
    static let recordTrainingDataKey = "recordTrainingData"
    static let weightUnitKey = "weightUnit"
    static let calibrateEveryWorkoutKey = "calibrateEveryWorkout"
    static let onboardedKey = "watchOnboarded"
    static let speakInstructionsKey = "speakInstructions"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            restTimeoutKey: 5.0,
            hapticEveryRepKey: true,
            recordTrainingDataKey: true,
            weightUnitKey: "kg",
            calibrateEveryWorkoutKey: true,
            speakInstructionsKey: true,
        ])
    }

    static var restTimeout: Double { UserDefaults.standard.double(forKey: restTimeoutKey) }
    static var hapticEveryRep: Bool { UserDefaults.standard.bool(forKey: hapticEveryRepKey) }
    static var recordTrainingData: Bool { UserDefaults.standard.bool(forKey: recordTrainingDataKey) }
    static var weightUnit: String { UserDefaults.standard.string(forKey: weightUnitKey) ?? "kg" }
    static var calibrateEveryWorkout: Bool { UserDefaults.standard.bool(forKey: calibrateEveryWorkoutKey) }
    static var speakInstructions: Bool { UserDefaults.standard.bool(forKey: speakInstructionsKey) }
}
