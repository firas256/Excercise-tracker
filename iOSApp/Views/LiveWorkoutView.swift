import SwiftUI
import UIKit

/// The workout on the iPhone while the watch does the sensing: live arm motion, rep count,
/// exercise guess, coaching cue, rest timer and all controls – no need to turn your wrist.
struct LiveWorkoutView: View {
    @EnvironmentObject var connectivity: PhoneConnectivityService
    @EnvironmentObject var store: WorkoutStore
    @State private var showExercisePicker = false
    @State private var confirmEnd = false
    @State private var dismissedReview: UUID?
    /// The big rep count grows and shrinks with the user's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var repCountSize: CGFloat = 84
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let state = connectivity.liveWorkout {
            content(state)
                .sheet(item: reviewBinding(state)) { pending in
                    PhoneSetReviewView(pending: pending)
                        .environmentObject(connectivity)
                        .presentationDetents([.large])
                }
                .sheet(isPresented: $showExercisePicker) {
                    PhoneExercisePicker(state: state)
                        .environmentObject(connectivity)
                }
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        } else {
            ProgressView()
        }
    }

    private func reviewBinding(_ state: LiveWorkoutState) -> Binding<PendingSetSummary?> {
        Binding(
            get: {
                guard let p = state.pendingSet, p.id != dismissedReview else { return nil }
                return p
            },
            set: { newValue in
                if newValue == nil, let id = state.pendingSet?.id { dismissedReview = id }
            }
        )
    }

    private func content(_ state: LiveWorkoutState) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                header(state)
                if let issue = state.backgroundIssue {
                    WatchBackgroundIssueBanner(issue: issue)
                }
                TimelineView(.periodic(from: .now, by: 2)) { context in
                    if isStale(at: context.date) {
                        Label("Waiting for your watch – keep it nearby.", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .font(.footnote)
                            .foregroundStyle(Color.warning)
                    }
                }
                ArmMotionView(frames: connectivity.frames, lastArrival: connectivity.lastFrameArrival,
                              forearmLength: store.calibration?.body?.forearmLength ?? MotionFrameBuilder.defaultWatchRadius)
                    .frame(height: 280)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
                repBlock(state)
                exerciseBlock(state)
                controls(state)
            }
            .padding()
        }
        .confirmationDialog("End the workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) { connectivity.send(.endWorkout) }
        }
    }

    private func isStale(at date: Date) -> Bool {
        guard let last = connectivity.lastLiveUpdate else { return true }
        return date.timeIntervalSince(last) > 12
    }

    private func header(_ state: LiveWorkoutState) -> some View {
        HStack(spacing: 14) {
            Button {
                connectivity.liveWorkoutMinimized = true
            } label: {
                Image(systemName: "chevron.down.circle.fill").font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Minimize")
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Live workout").font(.headline)
                Text("Set \(state.completedSets + (state.status == .reviewing ? 0 : 1))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let start = state.workoutStartedAt {
                Text(start, style: .timer).font(.title3.monospacedDigit()).foregroundStyle(Color.warning)
            }
            if let hr = state.heartRate {
                Label("\(Int(hr))", systemImage: "heart.fill").foregroundStyle(Color.danger).font(.subheadline.bold())
            }
        }
    }

    private func repBlock(_ state: LiveWorkoutState) -> some View {
        VStack(spacing: 2) {
            Text("\(state.repCount)")
                .font(.system(size: repCountSize, weight: .bold, design: .rounded))
                .foregroundStyle(state.status == .inSet ? Color.brand : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: state.repCount)
            Text(state.repCount == 1 ? "rep" : "reps").font(.subheadline).foregroundStyle(.secondary)
            statusLine(state)
        }
    }

    @ViewBuilder private func statusLine(_ state: LiveWorkoutState) -> some View {
        switch state.status {
        case .inSet:
            Text(state.liveCue ?? "Tracking…")
                .font(.title3.bold())
                .foregroundStyle(state.lastRepFlagged ? Color.warning : Color.brand)
        case .reviewing:
            Button("Review set") { dismissedReview = nil }
                .font(.title3.bold())
        case .waitingForSet:
            if let rest = state.restStartedAt {
                HStack(spacing: 6) {
                    Text("Rest")
                    Text(rest, style: .timer).monospacedDigit()
                }
                .font(.title3.bold())
                .foregroundStyle(Color.warning)
            } else {
                Text("Start your set").font(.title3).foregroundStyle(.secondary)
            }
        case .ended:
            Text("Workout complete").font(.title3.bold()).foregroundStyle(Color.brand)
        }
    }

    private func exerciseBlock(_ state: LiveWorkoutState) -> some View {
        VStack(spacing: 8) {
            if let locked = state.lockedExercise {
                Label(locked.displayName, systemImage: "lock.fill").font(.title2.bold())
                Button("Back to auto-detect") { connectivity.send(.lockExercise(nil)) }
                    .font(.subheadline)
            } else if !state.candidates.isEmpty {
                Text("Looks like").font(.caption).foregroundStyle(.secondary)
                // Side by side; stacked when large text needs the width.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ForEach(state.candidates, id: \.exercise) { c in
                        Button {
                            connectivity.send(.lockExercise(c.exercise))
                        } label: {
                            VStack(spacing: 2) {
                                Text(c.exercise.displayName).font(.subheadline.bold())
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                // Primary, not secondary: the chip's tint behind it costs contrast.
                                Text("\(Int((c.probability * 100).rounded()))%").font(.caption).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background(c.exercise == state.candidates.first?.exercise ? Color.brand.opacity(0.18) : Color.gray.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Tap the right one to lock it for this exercise.").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Auto-detect – the exercise appears after ~3 reps").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    private func controls(_ state: LiveWorkoutState) -> some View {
        VStack(spacing: 10) {
            if state.status == .inSet {
                HStack {
                    Button {
                        connectivity.send(.endSet)
                    } label: {
                        Label("End set", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.onBrand)
                    Button(role: .destructive) {
                        connectivity.send(.discardSet)
                    } label: {
                        Label("Discard", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            Button {
                showExercisePicker = true
            } label: {
                Label("Choose exercise", systemImage: "list.bullet").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button(role: .destructive) {
                confirmEnd = true
            } label: {
                Label("End workout", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.danger)
        }
    }
}

/// Pick (lock) the exercise from the phone.
struct PhoneExercisePicker: View {
    @EnvironmentObject var connectivity: PhoneConnectivityService
    @Environment(\.dismiss) private var dismiss
    let state: LiveWorkoutState

    var body: some View {
        NavigationStack {
            List {
                Button {
                    connectivity.send(.lockExercise(nil))
                    dismiss()
                } label: {
                    row("Auto-detect", selected: state.lockedExercise == nil, symbol: "sparkles")
                }
                ForEach(ExerciseCategory.allCases, id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(ExerciseType.allCases.filter { $0.category == category }) { e in
                            Button {
                                connectivity.send(.lockExercise(e))
                                dismiss()
                            } label: {
                                row(e.displayName, selected: state.lockedExercise == e, symbol: e.symbolName)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func row(_ title: String, selected: Bool, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(Color.brand).frame(width: 26).accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.brand) }
        }
    }
}

/// Confirm or correct a finished set from the phone.
struct PhoneSetReviewView: View {
    @EnvironmentObject var connectivity: PhoneConnectivityService
    @Environment(\.dismiss) private var dismiss
    let pending: PendingSetSummary

    @State private var exercise: ExerciseType?
    @State private var reps = 0
    @State private var weight = 0.0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section("Exercise") {
                    ForEach(pending.candidates, id: \.exercise) { c in
                        Button {
                            exercise = c.exercise
                        } label: {
                            HStack {
                                Text(c.exercise.displayName).foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int((c.probability * 100).rounded()))%").foregroundStyle(.secondary)
                                if exercise == c.exercise { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand) }
                            }
                        }
                    }
                    Menu {
                        ForEach(ExerciseType.allCases) { e in
                            Button(e.displayName) { exercise = e }
                        }
                    } label: {
                        HStack {
                            Text("Something else…")
                            Spacer()
                            if let e = exercise, !pending.candidates.contains(where: { $0.exercise == e }) {
                                Text(e.displayName).foregroundStyle(Color.brand)
                            }
                        }
                    }
                }
                Section {
                    Stepper(value: $reps, in: 0...300) {
                        Text("\(reps) reps").font(.title2.bold())
                    }
                    Stepper(value: $weight, in: 0...500, step: pending.weightUnit == "kg" ? 2.5 : 5) {
                        Text(weight > 0 ? "\(weight.formatted()) \(pending.weightUnit)" : "No weight").font(.title3)
                    }
                }
                Section {
                    HStack(spacing: 14) {
                        ScoreBadge(score: pending.feedback.score, size: 48)
                        VStack(alignment: .leading) {
                            Text("Range \(Int(pending.feedback.averageRange.rounded()))\(pending.feedback.unit.symbol)")
                            Text(String(format: "%.1f s up · %.1f s down", pending.feedback.averageConcentric, pending.feedback.averageEccentric))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    ForEach(pending.feedback.tips, id: \.self) { FeedbackTipRow(tip: $0) }
                } header: {
                    Text("Feedback")
                }
            }
            .navigationTitle("Set done")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(role: .destructive) {
                        connectivity.send(.discardPendingSet(id: pending.id))
                        dismiss()
                    } label: {
                        Text("Discard").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        connectivity.send(.savePendingSet(id: pending.id, exercise: exercise, reps: reps,
                                                          weight: weight > 0 ? weight : nil))
                        dismiss()
                    } label: {
                        Text("Save set").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.onBrand)
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            exercise = pending.exercise
            reps = pending.repCount
            weight = pending.weight ?? 0
        }
    }
}
