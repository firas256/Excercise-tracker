import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var health: HealthPermissionService
    @EnvironmentObject var connectivity: PhoneConnectivityService
    @State private var exportURL: URL?
    @State private var confirmDeleteWorkouts = false
    @State private var confirmDeleteTraining = false

    var body: some View {
        NavigationStack {
            List {
                Section("Permissions & devices") {
                    HStack {
                        Label("Apple Health", systemImage: "heart.fill")
                        Spacer()
                        healthStatus
                    }
                    HStack {
                        Label("Apple Watch", systemImage: "applewatch")
                        Spacer()
                        Text(watchStatus).foregroundStyle(.secondary)
                    }
                    if let calibration = store.calibration {
                        LabeledContent("Last calibration") {
                            Text(calibration.date, style: .relative)
                        }
                    }
                }

                Section {
                    LabeledContent("Recorded sets", value: "\(store.totalTrainingRecordings)")
                    if !store.trainingCounts.isEmpty {
                        DisclosureGroup("Per exercise") {
                            ForEach(store.trainingCounts.keys.sorted { (store.trainingCounts[$0] ?? 0) > (store.trainingCounts[$1] ?? 0) }) { e in
                                LabeledContent(e.displayName, value: "\(store.trainingCounts[e] ?? 0)")
                            }
                        }
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share my recordings (.zip)", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            exportURL = store.makeTrainingExport()
                        } label: {
                            Label("Export my recordings", systemImage: "shippingbox")
                        }
                        .disabled(store.totalTrainingRecordings == 0)
                    }
                    #if DEBUG
                    NavigationLink("How to train your own model") { TrainingHelpView() }
                    #endif
                    Button("Delete recordings", role: .destructive) { confirmDeleteTraining = true }
                        .disabled(store.totalTrainingRecordings == 0)
                } header: {
                    Text("Motion recordings")
                } footer: {
                    Text("Each confirmed set can keep its motion data (watch Settings › Save sensor data). It powers the motion replay of your sets and stays on your devices; export it any time.")
                }

                Section("Data") {
                    #if DEBUG
                    Button("Add demo workout") { store.add(DemoData.makeWorkout(daysAgo: Int.random(in: 0...5))) }
                    #endif
                    Button("Delete all workouts", role: .destructive) { confirmDeleteWorkouts = true }
                }

                Section("About") {
                    NavigationLink("How Rep Coach works") { HowItWorksView() }
                    NavigationLink("Privacy, safety & credits") { AboutView() }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                health.refresh()
                store.refreshTrainingCounts()
                exportURL = nil
            }
            .confirmationDialog("Delete all workouts?", isPresented: $confirmDeleteWorkouts, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteAllWorkouts() }
            }
            .confirmationDialog("Delete all recorded sensor data?", isPresented: $confirmDeleteTraining, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteTrainingData()
                    exportURL = nil
                }
            }
        }
    }

    @ViewBuilder private var healthStatus: some View {
        switch health.status {
        case .requested:
            Text("Set up").foregroundStyle(.green)
        case .unavailable:
            Text("Unavailable").foregroundStyle(.secondary)
        case .notRequested, .unknown:
            Button("Allow") { health.request() }
        }
    }

    private var watchStatus: String {
        if !connectivity.isSupported { return "Not supported" }
        if !connectivity.isPaired { return "Not paired" }
        if !connectivity.isWatchAppInstalled { return "App not installed" }
        return connectivity.isReachable ? "Connected" : "Installed"
    }
}

struct TrainingHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Train a Core ML model (optional)").font(.title2.bold())
                Text("Rep Coach already guesses exercises with a built-in classifier that learns from every set you confirm. If you want an even better, fully custom model:")
                step(1, "Do your normal workouts with “Save sensor data” on (watch Settings). Confirm or correct the exercise after each set – that's the label.")
                step(2, "Here, tap “Prepare export” and share the .zip to your Mac (AirDrop works).")
                step(3, "On the Mac, open Xcode › Open Developer Tool › Create ML. New project › Activity Classifier.")
                step(4, "Training data: choose the unzipped TrainingData folder (one sub-folder per exercise). Features: all gravity_, accel_ and rotation_ columns. Prediction window: 100 (2 s at 50 Hz).")
                step(5, "Train, then export the model as ExerciseActivityClassifier.mlmodel and drag it into the “ExerciseTracker Watch App” target in Xcode.")
                step(6, "Build & run. The watch blends your model with the built-in classifier automatically.")
                Text("Aim for at least 5–10 sets per exercise. The data is in your calibrated arm frame, so it doesn't matter which wrist you wear the watch on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Train your model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.green.opacity(0.2), in: Circle())
            Text(text)
        }
    }
}

struct HowItWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Calibration", "Five held poses tell the app which watch axes point along your forearm and out of your palm. All motion is then converted into this “arm frame”, so the same exercise looks the same whether the watch is on your left or right wrist, crown left or right, or slightly rotated.")
                section("Rep counting", "The watch derives four signals from the accelerometer and gyroscope: forearm angle, rotation, vertical hand travel and push/pull travel. It picks the most rhythmic one (autocorrelation), then counts each full there-and-back cycle with hysteresis so small wobbles are ignored.")
                section("Exercise detection", "Two classifiers vote. A neural network (1-D CNN, Core ML, runs on the watch) looks at 5-second windows of calibrated arm motion; it was trained on recordings of 94 people doing 20 exercises. A second, personal classifier compares 14 orientation-independent features (forearm angles, grip, rotation axis, travel, tempo…) with biomechanical prototypes and updates them every time you confirm or correct a set, so it adapts to your form. The more sets you confirm, the more weight your personal classifier gets.")
                section("Credits", "The exercise-recognition model was trained on the RecoFit dataset: D. Morris, T. S. Saponas, A. Guillory, I. Kelner, “RecoFit: Using a Wearable Sensor to Find, Recognize, and Count Repetitive Exercises”, CHI 2014, Microsoft Research (CDLA-Permissive-2.0).")
                section("Feedback", "Range of motion is compared with your best reps in the set and, for curls, raises and triceps work, with absolute angles from calibration. Tempo is split into lifting and lowering phases. A drop in lifting speed (velocity loss) indicates fatigue.")
                section("Privacy", "All processing runs on your watch and iPhone. Nothing is uploaded.")
            }
            .padding()
        }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).foregroundStyle(.secondary)
        }
    }
}
