import Foundation

/// Persists workouts (JSON in Documents) and the sensor recordings used for ML training.
final class WorkoutStore: ObservableObject {
    @Published private(set) var workouts: [WorkoutRecord] = []
    @Published private(set) var calibration: CalibrationSummary?
    @Published private(set) var trainingCounts: [ExerciseType: Int] = [:]

    private let fileManager = FileManager.default
    private let documents: URL
    private var workoutsURL: URL { documents.appendingPathComponent("workouts.json") }
    private var calibrationURL: URL { documents.appendingPathComponent("calibration.json") }
    /// Documents/TrainingData/<exercise>/<set-id>.csv – the folder layout Create ML expects.
    var trainingDirectory: URL { documents.appendingPathComponent("TrainingData", isDirectory: true) }

    init() {
        documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        load()
        refreshTrainingCounts()
        // `-demoWorkout YES` launch argument: preload a demo workout (Simulator / screenshots).
        if UserDefaults.standard.bool(forKey: "demoWorkout"), workouts.isEmpty {
            let saveRecording: (UUID, ExerciseType, [ArmSample]) -> Void = { [trainingDirectory, fileManager] id, exercise, samples in
                let dir = trainingDirectory.appendingPathComponent(exercise.rawValue, isDirectory: true)
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                try? TrainingCSV.make(samples).write(to: dir.appendingPathComponent("\(id.uuidString).csv"), atomically: true, encoding: .utf8)
            }
            add(DemoData.makeWorkout(daysAgo: 0, recording: saveRecording))
            add(DemoData.makeWorkout(daysAgo: 2, recording: saveRecording))
            refreshTrainingCounts()
            if calibration == nil { setCalibration(DemoData.calibration()) }
        }
    }

    // MARK: Workouts

    func add(_ workout: WorkoutRecord) {
        if let i = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[i] = workout
        } else {
            workouts.append(workout)
        }
        workouts.sort { $0.startDate > $1.startDate }
        save()
    }

    func update(_ set: SetRecord, in workoutID: UUID) {
        guard let w = workouts.firstIndex(where: { $0.id == workoutID }),
              let s = workouts[w].sets.firstIndex(where: { $0.id == set.id }) else { return }
        let old = workouts[w].sets[s]
        workouts[w].sets[s] = set
        if old.exercise != set.exercise {
            relabelTrainingFile(setID: set.id, from: old.exercise, to: set.exercise)
        }
        save()
    }

    func delete(_ workout: WorkoutRecord) {
        workouts.removeAll { $0.id == workout.id }
        save()
    }

    func deleteAllWorkouts() {
        workouts.removeAll()
        save()
    }

    func setCalibration(_ summary: CalibrationSummary) {
        calibration = summary
        if let data = PayloadCoding.encode(summary) { try? data.write(to: calibrationURL, options: .atomic) }
    }

    private func load() {
        if let data = try? Data(contentsOf: workoutsURL),
           let list = PayloadCoding.decode([WorkoutRecord].self, from: data) {
            workouts = list.sorted { $0.startDate > $1.startDate }
        }
        if let data = try? Data(contentsOf: calibrationURL) {
            calibration = PayloadCoding.decode(CalibrationSummary.self, from: data)
        }
    }

    private func save() {
        if let data = PayloadCoding.encode(workouts) {
            try? data.write(to: workoutsURL, options: .atomic)
        }
    }

    // MARK: Training data

    /// Moves a received recording into the training folder. Safe to call from any thread.
    func storeTrainingFile(at url: URL, label: String, setID: String) {
        let dir = trainingDirectory.appendingPathComponent(label, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("\(setID).csv")
        try? fileManager.removeItem(at: destination)
        do {
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            try? fileManager.copyItem(at: url, to: destination)
        }
        DispatchQueue.main.async { self.refreshTrainingCounts() }
    }

    func relabelTrainingFile(setID: UUID, from old: ExerciseType, to new: ExerciseType) {
        let source = trainingDirectory.appendingPathComponent(old.rawValue).appendingPathComponent("\(setID.uuidString).csv")
        guard fileManager.fileExists(atPath: source.path) else { return }
        let dir = trainingDirectory.appendingPathComponent(new.rawValue, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fileManager.moveItem(at: source, to: dir.appendingPathComponent("\(setID.uuidString).csv"))
        refreshTrainingCounts()
    }

    func refreshTrainingCounts() {
        var counts: [ExerciseType: Int] = [:]
        for e in ExerciseType.allCases {
            let dir = trainingDirectory.appendingPathComponent(e.rawValue)
            let files = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
            let n = files.filter { $0.hasSuffix(".csv") }.count
            if n > 0 { counts[e] = n }
        }
        trainingCounts = counts
    }

    var totalTrainingRecordings: Int { trainingCounts.values.reduce(0, +) }

    /// The raw sensor recording of a set, if the watch sent one (it may sit in any exercise folder).
    func recordingURL(setID: UUID) -> URL? {
        let name = "\(setID.uuidString).csv"
        let folders = (try? fileManager.contentsOfDirectory(at: trainingDirectory, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent(name) }.first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Zips the training folder (via NSFileCoordinator) for sharing to a Mac / Create ML.
    func makeTrainingExport() -> URL? {
        guard fileManager.fileExists(atPath: trainingDirectory.path) else { return nil }
        var result: URL?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: trainingDirectory, options: .forUploading, error: &coordinatorError) { zipURL in
            let destination = fileManager.temporaryDirectory.appendingPathComponent("RepCoach-TrainingData.zip")
            try? fileManager.removeItem(at: destination)
            do {
                try fileManager.copyItem(at: zipURL, to: destination)
                result = destination
            } catch {
                result = nil
            }
        }
        return result
    }

    func deleteTrainingData() {
        try? fileManager.removeItem(at: trainingDirectory)
        refreshTrainingCounts()
    }

    // MARK: Stats

    func workouts(since date: Date) -> [WorkoutRecord] {
        workouts.filter { $0.startDate >= date }
    }

    func sets(for exercise: ExerciseType) -> [SetRecord] {
        workouts.flatMap { $0.sets }.filter { $0.exercise == exercise }
    }
}
