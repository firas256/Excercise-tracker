import SwiftUI

/// Three swipeable pages: controls ← live set → exercise picker.
struct WorkoutView: View {
    @EnvironmentObject var app: WatchAppModel
    @EnvironmentObject var workout: WorkoutViewModel
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            WorkoutControlsView().tag(0)
            LiveSetView().tag(1)
            ExercisePickerView(selection: $workout.lockedExercise, allowsAuto: true) {
                page = 1
            }
            .tag(2)
        }
        .tabViewStyle(.page)
        .sheet(item: pendingBinding) { pending in
            SetReviewView(pending: pending)
        }
    }

    /// Dismissing the summary (swipe / close button) keeps the set with the detected values.
    private var pendingBinding: Binding<WorkoutViewModel.PendingSet?> {
        Binding(
            get: { workout.pendingSet },
            set: { newValue in
                if newValue == nil, workout.pendingSet != nil {
                    workout.confirmPendingSet(exercise: nil, reps: nil, weight: nil)
                }
            }
        )
    }
}

struct LiveSetView: View {
    @EnvironmentObject var workout: WorkoutViewModel
    @EnvironmentObject var session: WorkoutSessionService

    var body: some View {
        VStack(spacing: 2) {
            exerciseLine
            Text("\(workout.repCount)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(workout.status == .inSet ? Color.green : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: workout.repCount)
            Text(workout.repCount == 1 ? "rep" : "reps")
                .font(.caption2)
                .foregroundStyle(.secondary)
            statusLine
            HStack(spacing: 10) {
                if let hr = session.heartRate {
                    Label("\(Int(hr))", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
                Text("Set \(workout.completedSets.count + 1)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
    }

    @ViewBuilder private var exerciseLine: some View {
        if let locked = workout.lockedExercise {
            Label(locked.displayName, systemImage: "lock.fill")
                .font(.footnote)
                .lineLimit(1)
        } else if let guess = workout.candidates.first {
            Text("\(guess.exercise.displayName)? \(Int(guess.probability * 100))%")
                .font(.footnote)
                .lineLimit(1)
        } else {
            Text("Auto-detect")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch workout.status {
        case .inSet:
            Text(workout.liveCue ?? "Tracking…")
                .font(.footnote)
                .foregroundStyle(workout.lastRepFlagged ? Color.orange : Color.green)
                .lineLimit(1)
        case .reviewing:
            Text("Set done").font(.footnote)
        case .waitingForSet:
            if let rest = workout.restStartedAt {
                HStack(spacing: 4) {
                    Text("Rest")
                    Text(rest, style: .timer)
                }
                .font(.footnote)
                .foregroundStyle(.yellow)
            } else {
                Text("Start your set").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutControlsView: View {
    @EnvironmentObject var app: WatchAppModel
    @EnvironmentObject var workout: WorkoutViewModel
    @EnvironmentObject var session: WorkoutSessionService

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let start = session.startDate {
                    Text(start, style: .timer)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.yellow)
                }
                HStack {
                    if session.activeEnergy > 0 {
                        Text("\(Int(session.activeEnergy)) kcal")
                    }
                    Text(workout.completedSets.count == 1 ? "1 set" : "\(workout.completedSets.count) sets")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if workout.status == .inSet {
                    Button {
                        workout.endSetNow()
                    } label: {
                        Label("End Set", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                    Button {
                        workout.cancelCurrentSet()
                    } label: {
                        Label("Discard Set", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button(role: .destructive) {
                    app.endWorkout()
                } label: {
                    Label("End Workout", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
                if !session.usingHealthKit {
                    Text("Health is off: heart rate isn't recorded.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
