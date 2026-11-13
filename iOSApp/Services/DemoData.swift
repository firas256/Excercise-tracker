import Foundation

/// Builds a realistic demo workout by running the real analysis pipeline on simulated motion,
/// so the app can be explored before the first watch workout (or in the Simulator).
enum DemoData {
    /// A calibration run through the real calibration engine on simulated motion (arm 0.55 m).
    static func calibration() -> CalibrationSummary {
        let engine = CalibrationEngine()
        var events = engine.start()
        for sample in SyntheticCalibration.samples(armLength: 0.55, overheadElevation: 82, noiseSeed: 3) {
            events += engine.ingest(sample)
        }
        for case .finished(let profile) in events { return CalibrationSummary(profile: profile) }
        return CalibrationSummary(profile: .defaultProfile())
    }

    /// `recording` receives each set's raw samples (used to give demo sets a motion replay).
    static func makeWorkout(daysAgo: Int = 1, recording: ((UUID, ExerciseType, [ArmSample]) -> Void)? = nil) -> WorkoutRecord {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        var t = start
        var sets: [SetRecord] = []

        func addSet(_ exercise: ExerciseType, weight: Double, configure: (inout SyntheticMotion.Options) -> Void) {
            var options = SyntheticMotion.Options()
            options.seed = UInt64(sets.count + 1)
            configure(&options)
            guard let samples = SyntheticMotion.generate(exercise, options: options) else { return }
            let analysis = SetAnalyzer().analyze(samples)
            let known = SetAnalyzer().analyze(samples, lockedExercise: exercise)
            let duration = SyntheticMotion.duration(options)
            let id = UUID()
            recording?(id, exercise, samples)
            sets.append(SetRecord(
                id: id,
                exercise: exercise,
                detectedExercise: analysis.candidates.first?.exercise,
                detectionConfidence: analysis.confidence,
                alternatives: Array(analysis.candidates.prefix(3)),
                userCorrectedExercise: analysis.candidates.first?.exercise != exercise,
                repCount: analysis.repCount,
                detectedRepCount: analysis.repCount,
                reps: known.reps,
                feedback: known.feedback,
                signal: analysis.detection?.signal ?? exercise.preferredSignal,
                weight: weight,
                weightUnit: "kg",
                startDate: t,
                endDate: t.addingTimeInterval(duration),
                features: analysis.features
            ))
            t = t.addingTimeInterval(duration + 90)
        }

        addSet(.bicepCurl, weight: 12.5) { $0.reps = 10 }
        addSet(.bicepCurl, weight: 12.5) {
            $0.reps = 8
            $0.amplitudes = [1, 1, 1, 1, 1, 0.9, 0.7, 0.6]
        }
        addSet(.shoulderPress, weight: 16) {
            $0.reps = 8
            $0.eccentric = 0.6
        }
        addSet(.lateralRaise, weight: 8) { $0.reps = 12 }
        addSet(.seatedCableRow, weight: 45) { $0.reps = 10 }
        addSet(.tricepsPushdown, weight: 25) {
            $0.reps = 12
            $0.concentric = 0.9
            $0.eccentric = 1.8
        }

        return WorkoutRecord(id: UUID(), startDate: start, endDate: t, sets: sets,
                             averageHeartRate: 118, activeEnergyKilocalories: 145, calibratedAt: start)
    }
}
