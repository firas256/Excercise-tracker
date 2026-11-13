import Foundation

/// Combines the personal prototype classifier with a model trained on other people's recordings
/// that only knows some exercises (the built-in Core ML model has never seen a triceps pushdown or
/// a hammer curl, for example).
///
/// The model may only move probability *between the exercises it knows*. Without this it would
/// always vote for the nearest exercise it does know – "bicep curl" for a pushdown – and with its
/// large weight drown out everything else.
enum ClassifierBlend {
    static func combine(prototype: [ExerciseCandidate], model: [ExerciseCandidate],
                        modelKnows known: Set<ExerciseType>, modelWeight w: Double) -> [ExerciseCandidate] {
        let considered = Set(prototype.map { $0.exercise })
        let known = known.intersection(considered)
        let knownMass = prototype.filter { known.contains($0.exercise) }.reduce(0) { $0 + $1.probability }
        let modelMass = model.filter { known.contains($0.exercise) }.reduce(0) { $0 + $1.probability }
        guard modelMass > 0, knownMass > 0 else { return prototype }
        let w = SignalMath.clamp(w, 0, 1)
        var combined: [ExerciseType: Double] = [:]
        for c in prototype {
            // Exercises the model doesn't know keep the prototype's probability untouched.
            combined[c.exercise] = known.contains(c.exercise) ? (1 - w) * c.probability : c.probability
        }
        for c in model where known.contains(c.exercise) {
            combined[c.exercise, default: 0] += w * knownMass * c.probability / modelMass
        }
        let total = combined.values.reduce(0, +)
        return combined.map { ExerciseCandidate(exercise: $0.key, probability: $0.value / max(total, 1e-12)) }
            .sorted { $0.probability > $1.probability }
    }
}
