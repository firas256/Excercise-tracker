import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject var store: WorkoutStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(ExerciseType.allCases.filter { $0.category == category }) { e in
                            NavigationLink {
                                ExerciseDetailView(exercise: e)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(e.displayName)
                                        Text(e.muscleGroup).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    TrackingQualityBadge(quality: e.trackingQuality)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exercises")
        }
    }
}

struct ExerciseDetailView: View {
    @EnvironmentObject var store: WorkoutStore
    let exercise: ExerciseType

    private var history: [SetRecord] { store.sets(for: exercise) }

    var body: some View {
        List {
            Section("Form cue") {
                Text(exercise.formCue)
            }
            Section("How the watch tracks it") {
                LabeledContent("Tracking", value: exercise.trackingQuality.displayName)
                LabeledContent("Measured with", value: signalDescription)
                LabeledContent("Auto-detect", value: exercise.isAutoDetectable ? "Yes" : "Pick it on the watch")
                Text(qualityExplanation).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your history") {
                if history.isEmpty {
                    Text("No sets yet").foregroundStyle(.secondary)
                } else {
                    LabeledContent("Sets", value: "\(history.count)")
                    LabeledContent("Total reps", value: "\(history.reduce(0) { $0 + $1.repCount })")
                    if let best = history.compactMap({ $0.weight }).max() {
                        LabeledContent("Heaviest", value: "\(best.formatted()) \(history.first?.weightUnit ?? "kg")")
                    }
                    LabeledContent("Average form score", value: "\(history.reduce(0) { $0 + $1.feedback.score } / history.count)")
                }
            }
        }
        .navigationTitle(exercise.displayName)
    }

    private var signalDescription: String {
        switch exercise.preferredSignal {
        case .elevation: return "Forearm angle (gyro + gravity)"
        case .rotation: return "Arm rotation (gyroscope)"
        case .vertical: return "Vertical hand travel (accelerometer)"
        case .forearm: return "Push/pull travel (accelerometer)"
        }
    }

    private var qualityExplanation: String {
        switch exercise.trackingQuality {
        case .good: return "Your wrist moves through a large, distinctive path, so reps, range of motion and tempo are measured reliably."
        case .moderate: return "Your hands move mostly in a straight line. Rep counting and tempo work well; range of motion is an estimate from the accelerometer."
        case .limited: return "Your hands stay fixed (e.g. on a handle or the floor), so the watch only sees small movements. Select the exercise manually and check the count."
        }
    }
}
