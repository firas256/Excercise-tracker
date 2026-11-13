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
                    startOnWatchCard
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
            .disabled(starting)
            Text(startMessage ?? "Calibration instructions are shown and read aloud here, so you don't need to look at your watch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 54))
                .foregroundStyle(.green)
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(value: "\(thisWeek.count)", label: "Workouts", symbol: "figure.strengthtraining.traditional")
                StatTile(value: "\(sets)", label: "Sets", symbol: "square.stack.3d.up.fill")
                StatTile(value: "\(reps)", label: "Reps", symbol: "repeat")
                StatTile(value: thisWeek.isEmpty ? "–" : "\(score)", label: "Avg form score", symbol: "star.fill")
            }
        }
    }

    private var repsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reps per day").font(.headline)
            Chart(repsPerDay) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Reps", d.reps))
                    .foregroundStyle(Color.green.gradient)
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
                    Text(w.exercises.map { $0.displayName }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
            Image(systemName: "scope").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                if let c = store.calibration {
                    Text("Watch calibrated").font(.headline)
                    Text("\(c.date, style: .relative) ago · \(c.wrist.rawValue) wrist · overhead reach \(Int(c.overheadElevation))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
