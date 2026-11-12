import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject var app: WatchAppModel
    let record: WorkoutRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workout complete")
                    .font(.headline)
                    .foregroundStyle(.green)
                HStack {
                    stat("\(record.sets.count)", "sets")
                    stat("\(record.totalReps)", "reps")
                    stat("\(record.averageScore)", "score")
                }
                if let hr = record.averageHeartRate {
                    Label("\(Int(hr)) bpm avg", systemImage: "heart.fill").font(.footnote)
                }
                if let kcal = record.activeEnergyKilocalories {
                    Label("\(Int(kcal)) kcal", systemImage: "flame.fill").font(.footnote)
                }
                Divider()
                ForEach(record.sets) { set in
                    HStack {
                        Text(set.exercise.displayName).font(.footnote).lineLimit(1)
                        Spacer()
                        Text("\(set.repCount)×").font(.footnote.bold())
                    }
                }
                Text("Details are on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Done") { app.screen = .home }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
