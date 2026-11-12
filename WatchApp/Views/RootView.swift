import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: WatchAppModel

    var body: some View {
        switch app.screen {
        case .onboarding:
            OnboardingView()
        case .home:
            HomeView()
        case .calibration:
            CalibrationView(model: app.calibrationModel)
        case .workout:
            WorkoutView()
        case .summary(let record):
            WorkoutSummaryView(record: record)
        }
    }
}

/// First launch: explain and request the permissions the app needs.
struct OnboardingView: View {
    @EnvironmentObject var app: WatchAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Rep Coach")
                    .font(.title3.bold())
                Text("Counts your reps, guesses the exercise and coaches your range and tempo using the watch's motion sensors.")
                    .font(.footnote)
                Label("Health: workouts, heart rate & calories – keeps tracking while your wrist is down.", systemImage: "heart.fill")
                    .font(.footnote)
                Label("Motion sensors: accelerometer & gyroscope, processed on your watch.", systemImage: "gyroscope")
                    .font(.footnote)
                Button("Allow Access") { app.requestPermissions() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button("Not Now") { app.skipPermissions() }
                    .font(.footnote)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var app: WatchAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Button {
                        app.startWorkout()
                    } label: {
                        Label("Start Workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        app.beginCalibration(startsWorkout: false)
                    } label: {
                        Label("Calibrate", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }

                    calibrationStatus

                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Rep Coach")
        }
    }

    @ViewBuilder private var calibrationStatus: some View {
        if let c = app.calibration {
            Text("Calibrated \(c.createdAt, style: .relative) ago")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Not calibrated yet – you'll be guided before your first set.")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }
}
