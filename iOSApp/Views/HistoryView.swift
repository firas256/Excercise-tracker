import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: WorkoutStore

    var body: some View {
        NavigationStack {
            Group {
                if store.workouts.isEmpty {
                    ContentUnavailableView("No workouts", systemImage: "clock",
                                           description: Text("Finished workouts from your watch show up here."))
                } else {
                    List {
                        ForEach(store.workouts) { w in
                            NavigationLink(value: w.id) { WorkoutRow(workout: w) }
                        }
                        .onDelete { offsets in
                            offsets.map { store.workouts[$0] }.forEach(store.delete)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in WorkoutDetailView(workoutID: id) }
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.startDate, format: .dateTime.day().month().hour().minute()).font(.headline)
                Text(workout.exercises.map { $0.displayName }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(workout.sets.count) sets · \(workout.totalReps) reps").font(.caption)
            }
            Spacer()
            ScoreBadge(score: workout.averageScore)
        }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject var store: WorkoutStore
    let workoutID: UUID

    private var workout: WorkoutRecord? { store.workouts.first { $0.id == workoutID } }

    var body: some View {
        if let w = workout {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        mini("\(w.sets.count)", "sets")
                        mini("\(w.totalReps)", "reps")
                        mini(w.duration.minutesSeconds, "duration")
                        mini(w.averageHeartRate.map { "\(Int($0))" } ?? "–", "avg bpm")
                        mini(w.activeEnergyKilocalories.map { "\(Int($0))" } ?? "–", "kcal")
                        mini("\(w.averageScore)", "form score")
                    }
                    .padding(.vertical, 4)
                }
                Section("Sets") {
                    ForEach(Array(w.sets.enumerated()), id: \.element.id) { index, set in
                        NavigationLink {
                            SetDetailView(workoutID: w.id, setID: set.id)
                        } label: {
                            SetRow(index: index + 1, set: set)
                        }
                    }
                }
            }
            .navigationTitle(Text(w.startDate, format: .dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Workout deleted", systemImage: "trash")
        }
    }

    private func mini(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SetRow: View {
    let index: Int
    let set: SetRecord

    var body: some View {
        HStack {
            Text("\(index)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.green.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(set.exercise.displayName).font(.headline)
                HStack(spacing: 6) {
                    Text("\(set.repCount) reps")
                    if let w = set.weight { Text("· \(w, specifier: "%g") \(set.weightUnit)") }
                    Text("· \(Int(set.feedback.averageRange.rounded()))\(set.feedback.unit.symbol)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ScoreBadge(score: set.feedback.score, size: 34)
        }
    }
}

struct SetDetailView: View {
    @EnvironmentObject var store: WorkoutStore
    let workoutID: UUID
    let setID: UUID

    private var set: SetRecord? {
        store.workouts.first { $0.id == workoutID }?.sets.first { $0.id == setID }
    }

    var body: some View {
        if let set {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Menu {
                                ForEach(ExerciseType.allCases) { e in
                                    Button(e.displayName) { update { $0.exercise = e; $0.userCorrectedExercise = $0.detectedExercise != nil && $0.detectedExercise != e } }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(set.exercise.displayName).font(.title2.bold())
                                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                                }
                            }
                            Text(detectionText(set)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ScoreBadge(score: set.feedback.score, size: 56)
                    }
                    Stepper("\(set.repCount) reps", value: Binding(get: { set.repCount }, set: { v in update { $0.repCount = max(0, v) } }), in: 0...300)
                    if set.repCount != set.detectedRepCount {
                        Text("Watch counted \(set.detectedRepCount)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Feedback") {
                    ForEach(set.feedback.tips, id: \.self) { FeedbackTipRow(tip: $0) }
                }

                if let url = store.recordingURL(setID: set.id) {
                    Section {
                        MotionReplayView(recording: url, reps: set.reps,
                                         forearmLength: store.calibration?.body?.forearmLength ?? MotionFrameBuilder.defaultWatchRadius)
                    } header: {
                        Text("Arm motion replay")
                    } footer: {
                        Text("Rebuilt from the watch's sensors. Check it matches what you did. Green: forearm and the hand's path. Orange: the way your palm faces.")
                    }
                }

                if !set.reps.isEmpty {
                    Section("Range of motion per rep") {
                        Chart(set.reps) { r in
                            BarMark(x: .value("Rep", r.index), y: .value("Range", r.rangeOfMotion))
                                .foregroundStyle(r.issues.contains(.partialRange) ? Color.orange : Color.green)
                                .cornerRadius(3)
                        }
                        .chartYAxisLabel(set.feedback.unit == .degrees ? "degrees" : "cm")
                        .frame(height: 160)
                    }
                    Section("Tempo per rep") {
                        Chart {
                            ForEach(set.reps) { r in
                                BarMark(x: .value("Rep", r.index), y: .value("Seconds", r.concentricDuration))
                                    .foregroundStyle(by: .value("Phase", "Lift"))
                                BarMark(x: .value("Rep", r.index), y: .value("Seconds", r.eccentricDuration))
                                    .foregroundStyle(by: .value("Phase", "Lower"))
                            }
                        }
                        .chartForegroundStyleScale(["Lift": Color.green, "Lower": Color.blue])
                        .chartYAxisLabel("seconds")
                        .frame(height: 160)
                    }
                    Section {
                        Chart(set.reps) { r in
                            LineMark(x: .value("Rep", r.index), y: .value("Speed", r.meanConcentricSpeed))
                                .symbol(.circle)
                                .foregroundStyle(.purple)
                        }
                        .chartYAxisLabel(set.feedback.unit == .degrees ? "°/s" : "cm/s")
                        .frame(height: 140)
                    } header: {
                        Text("Lifting speed")
                    } footer: {
                        Text(String(format: "Speed loss %.0f%%. Big drops mean you are close to failure (velocity-based training).", set.feedback.velocityLoss * 100))
                    }
                    Section("Reps") {
                        ForEach(set.reps) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Rep \(r.index)").font(.subheadline.bold())
                                    Spacer()
                                    Text("\(Int(r.rangeOfMotion.rounded()))\(r.unit.symbol)")
                                    Text(String(format: "%.1fs ↑ %.1fs ↓", r.concentricDuration, r.eccentricDuration))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                if !r.issues.isEmpty {
                                    Text(r.issues.map { $0.shortText }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Set")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Set not found", systemImage: "questionmark")
        }
    }

    private func detectionText(_ set: SetRecord) -> String {
        guard let detected = set.detectedExercise else { return "Chosen manually" }
        let pct = Int(set.detectionConfidence * 100)
        if set.userCorrectedExercise { return "Watch guessed \(detected.displayName) (\(pct)%) – corrected" }
        return "Auto-detected (\(pct)% confident)"
    }

    private func update(_ change: (inout SetRecord) -> Void) {
        guard var s = set else { return }
        change(&s)
        store.update(s, in: workoutID)
    }
}
