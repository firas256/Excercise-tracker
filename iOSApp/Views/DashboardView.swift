import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var health: HealthPermissionService
    @EnvironmentObject var connectivity: PhoneConnectivityService
    @State private var startMessage: String?
    @State private var starting = false

    private var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var thisWeek: [WorkoutRecord] { store.workouts(since: weekStart) }

    private struct DayReps: Identifiable {
        let day: Date
        let reps: Int
        var id: Date { day }
    }

    private var repsPerDay: [DayReps] {
        let cal = Calendar.current
        return (0..<7).compactMap { offset -> DayReps? in
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let reps = thisWeek.filter { cal.isDate($0.startDate, inSameDayAs: day) }.reduce(0) { $0 + $1.totalReps }
            return DayReps(day: day, reps: reps)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if connectivity.liveWorkout != nil {
                        liveWorkoutBanner
                    } else {
                        startOnWatchCard
                    }
                    if store.workouts.isEmpty {
                        emptyState
                    } else {
                        weekStats
                        repsChart
                        if let last = store.workouts.first {
                            lastWorkoutCard(last)
                        }
                    }
                    calibrationCard
                }
                .padding()
            }
            .navigationTitle("Rep Coach")
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
        }
    }

    /// Why starting on the watch can't work yet (nil when it can, or when it can't be told).
    private var watchProblem: String? {
        guard connectivity.isSupported, connectivity.isActivated else { return nil }
        if !connectivity.isPaired { return "No Apple Watch is paired with this iPhone – Rep Coach needs one." }
        if !connectivity.isWatchAppInstalled {
            return "Rep Coach isn't on your watch yet: open the Watch app › My Watch › Available Apps › Install."
        }
        return nil
    }

    /// A workout is running on the watch but its screen was minimized.
    private var liveWorkoutBanner: some View {
        Button {
            connectivity.liveWorkoutMinimized = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in progress").font(.headline)
                    if let state = connectivity.liveWorkout {
                        Text("\(state.completedSets) sets done · \(state.status == .inSet ? "\(state.repCount) reps" : "resting")")
                            .font(.caption)
                    }
                }
                Spacer()
                Text("Open").font(.subheadline.bold())
                Image(systemName: "chevron.up")
            }
            .padding()
            .foregroundStyle(Color.onBrand)
            .background(Color.brand, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("liveWorkoutBanner")
    }

    /// Starts the workout on the watch from here; the calibration steps then appear on this screen.
    private var startOnWatchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                starting = true
                startMessage = nil
                health.startWorkoutOnWatch { error in
                    starting = false
                    startMessage = error.map { "Couldn't start on the watch (\($0)). Open Rep Coach on your watch and tap Start Workout." }
                        ?? "Starting on your watch – keep this screen open to follow the calibration."
                }
            } label: {
                Label(starting ? "Starting…" : "Start workout on Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.onBrand)
            .disabled(starting)
            Text(startMessage ?? "Calibration instructions are shown and read aloud here, so you don't need to look at your watch.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let problem = watchProblem {
                Label(problem, systemImage: "applewatch.slash")
                    .font(.caption)
                    .foregroundStyle(Color.warning)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 54))
                .foregroundStyle(Color.brand)
                .accessibilityHidden(true)
            Text("No workouts yet").font(.title2.bold())
            Text("Open Rep Coach on your Apple Watch and tap Start Workout. Your sets appear here automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Load demo workout") { store.add(DemoData.makeWorkout()) }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var weekStats: some View {
        let sets = thisWeek.reduce(0) { $0 + $1.sets.count }
        let reps = thisWeek.reduce(0) { $0 + $1.totalReps }
        let score = thisWeek.isEmpty ? 0 : thisWeek.reduce(0) { $0 + $1.averageScore } / thisWeek.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days").font(.headline)
            // A plain Grid (not lazy) so the tiles re-measure for every text size.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    StatTile(value: "\(thisWeek.count)", label: "Workouts", symbol: "figure.strengthtraining.traditional")
                    StatTile(value: "\(sets)", label: "Sets", symbol: "square.stack.3d.up.fill")
                }
                GridRow {
                    StatTile(value: "\(reps)", label: "Reps", symbol: "repeat")
                    StatTile(value: thisWeek.isEmpty ? "–" : "\(score)", label: "Avg form score", symbol: "star.fill")
                }
            }
        }
    }

    private var repsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reps per day").font(.headline)
            Chart(repsPerDay) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Reps", d.reps))
                    .foregroundStyle(Color.brand.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func lastWorkoutCard(_ w: WorkoutRecord) -> some View {
        NavigationLink(value: w.id) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last workout").font(.caption).foregroundStyle(.secondary)
                    Text(w.startDate, format: .dateTime.weekday(.wide).hour().minute()).font(.headline)
                    Text(w.exerciseSummary())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(w.sets.count) sets · \(w.totalReps) reps · \(w.duration.minutesSeconds)")
                        .font(.caption)
                }
                Spacer()
                ScoreBadge(score: w.averageScore, size: 50)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var calibrationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "scope").font(.title2).foregroundStyle(Color.brand).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let c = store.calibration {
                    Text("Watch calibrated").font(.headline)
                    Text("\(c.date, style: .relative) ago · \(c.wrist.rawValue) wrist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let body = c.body {
                        BodyMeasurementsView(measurements: body)
                    }
                } else {
                    Text("Calibrate on your watch").font(.headline)
                    Text("Before tracking, the watch guides you through 5 poses: arm down, forward, palm up, to the side and overhead. It vibrates as each pose is captured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The personal measurements calibration took, which tailor tracking and feedback to the user.
struct BodyMeasurementsView: View {
    let measurements: BodyProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your measurements").font(.subheadline.bold()).padding(.top, 4)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                if measurements.isArmLengthMeasured {
                    row("Arm (shoulder to watch)", cm(measurements.armLength))
                    row("Forearm (elbow to watch)", "≈ " + cm(measurements.forearmLength))
                    row("Height", String(format: "≈ %.2f m", measurements.estimatedHeight))
                    row("Shoulder height", String(format: "≈ %.2f m", measurements.shoulderHeight))
                }
                row("Overhead reach", "\(Int(measurements.overheadElevation.rounded()))°")
                row("Palm turn (down → up)", "\(Int(measurements.supinationRange.rounded()))°")
            }
            .font(.caption)
            Text(measurements.isArmLengthMeasured
                 ? "Measured from how far your watch rose as your straight arm swung up; forearm and height are estimated from typical body proportions. Used for exercise recognition, form checks and the arm animation."
                 : "Arm length wasn't measured – keep your arm straight when raising it forward during calibration. Average proportions are used meanwhile.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func cm(_ metres: Double) -> String { "\(Int((metres * 100).rounded())) cm" }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
