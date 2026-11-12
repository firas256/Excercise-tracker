import SwiftUI

/// Shown when a set ends: confirm/correct the exercise and rep count, add weight, read feedback.
struct SetReviewView: View {
    @EnvironmentObject var workout: WorkoutViewModel
    let pending: WorkoutViewModel.PendingSet

    @State private var exercise: ExerciseType?
    @State private var reps: Int = 0
    @State private var weight: Double = 0
    @State private var initialized = false

    private var analysis: SetAnalysis { pending.completed.analysis }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink {
                        ExercisePickerView(selection: $exercise, allowsAuto: false,
                                           suggestions: analysis.candidates.prefix(3).map { $0.exercise })
                    } label: {
                        VStack(alignment: .leading) {
                            Text(exercise?.displayName ?? "Choose exercise").font(.headline)
                            if workout.lockedExercise == nil, let c = analysis.candidates.first {
                                Text("Detected \(Int(c.probability * 100))% · tap to change")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Stepper(value: $reps, in: 0...200) {
                        Text("\(reps) reps").font(.title3.bold())
                    }

                    Stepper(value: $weight, in: 0...500, step: WatchSettings.weightUnit == "kg" ? 2.5 : 5) {
                        Text(weight > 0 ? "\(weight, specifier: "%g") \(WatchSettings.weightUnit)" : "No weight")
                    }

                    scoreRow

                    ForEach(analysis.feedback.tips, id: \.self) { tip in
                        TipRow(tip: tip)
                    }

                    Button {
                        workout.confirmPendingSet(exercise: exercise, reps: reps, weight: weight > 0 ? weight : nil)
                    } label: {
                        Label("Save Set", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Discard", role: .destructive) { workout.discardPendingSet() }
                        .font(.footnote)
                }
            }
            .navigationTitle("Set done")
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            exercise = analysis.exercise
            reps = analysis.repCount
            if let e = analysis.exercise, let w = workout.store.lastWeight(for: e) { weight = w }
        }
    }

    private var scoreRow: some View {
        let f = analysis.feedback
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: Double(f.score) / 100)
                    .stroke(scoreColor(f.score), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(f.score)").font(.footnote.bold())
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Range \(Int(f.averageRange.rounded()))\(f.unit.symbol)")
                Text(String(format: "%.1fs up · %.1fs down", f.averageConcentric, f.averageEccentric))
            }
            .font(.caption2)
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        s >= 85 ? .green : (s >= 65 ? .yellow : .orange)
    }
}

struct TipRow: View {
    let tip: FeedbackTip

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(tip.title).font(.caption.bold())
                Text(tip.detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var symbol: String {
        switch tip.kind {
        case .positive: return "hand.thumbsup.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch tip.kind {
        case .positive: return .green
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
