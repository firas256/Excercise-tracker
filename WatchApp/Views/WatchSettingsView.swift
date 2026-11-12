import SwiftUI

struct WatchSettingsView: View {
    @EnvironmentObject var app: WatchAppModel
    @AppStorage(WatchSettings.restTimeoutKey) private var restTimeout = 5.0
    @AppStorage(WatchSettings.hapticEveryRepKey) private var hapticEveryRep = true
    @AppStorage(WatchSettings.recordTrainingDataKey) private var recordTrainingData = true
    @AppStorage(WatchSettings.weightUnitKey) private var weightUnit = "kg"
    @AppStorage(WatchSettings.calibrateEveryWorkoutKey) private var calibrateEveryWorkout = true
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                Toggle("Calibrate every workout", isOn: $calibrateEveryWorkout)
                Toggle("Tap on every rep", isOn: $hapticEveryRep)
            }
            Section {
                Stepper(value: $restTimeout, in: 3...12, step: 1) {
                    Text("Set ends after \(Int(restTimeout)) s rest")
                }
            } footer: {
                Text("How long you must be still before a set is considered finished.")
            }
            Section {
                Picker("Weight unit", selection: $weightUnit) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lb")
                }
            }
            Section {
                Toggle("Save sensor data", isOn: $recordTrainingData)
            } footer: {
                Text("Sends each confirmed set's motion data to your iPhone so you can train your own Core ML model later.")
            }
            Section {
                Text("Learned from \(app.store.personalization.totalExamples) confirmed sets")
                    .font(.footnote)
                Button("Reset learning", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Forget everything the classifier learned from your sets?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { app.store.resetLearning() }
        }
    }
}
