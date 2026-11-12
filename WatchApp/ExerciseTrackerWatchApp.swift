import SwiftUI

@main
struct ExerciseTrackerWatchApp: App {
    @StateObject private var model = WatchAppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.workout)
                .environmentObject(model.session)
        }
    }
}

/// Top-level navigation and workout lifecycle on the watch.
final class WatchAppModel: ObservableObject {
    enum Screen: Equatable {
        case onboarding
        case home
        /// Calibration; `startsWorkout` continues into tracking when done.
        case calibration(startsWorkout: Bool)
        case workout
        case summary(WorkoutRecord)
    }

    @Published var screen: Screen
    @Published private(set) var calibration: CalibrationProfile?

    let store = WatchStore()
    let session = WorkoutSessionService()
    let workout: WorkoutViewModel
    let calibrationModel = CalibrationViewModel()

    init() {
        WatchSettings.registerDefaults()
        workout = WorkoutViewModel(store: store)
        calibration = store.calibration
        screen = UserDefaults.standard.bool(forKey: WatchSettings.onboardedKey) ? .home : .onboarding
        WatchConnectivityService.shared.activate()
    }

    /// Asks for every permission the app needs, up front.
    func requestPermissions() {
        session.requestAuthorization { _ in
            UserDefaults.standard.set(true, forKey: WatchSettings.onboardedKey)
            self.screen = .home
        }
    }

    func skipPermissions() {
        UserDefaults.standard.set(true, forKey: WatchSettings.onboardedKey)
        screen = .home
    }

    func startWorkout() {
        session.start()
        if WatchSettings.calibrateEveryWorkout || calibration == nil {
            beginCalibration(startsWorkout: true)
        } else {
            beginTracking()
        }
    }

    func beginCalibration(startsWorkout: Bool) {
        screen = .calibration(startsWorkout: startsWorkout)
        calibrationModel.onFinish = { [weak self] profile in
            guard let self else { return }
            self.store.calibration = profile
            self.calibration = profile
            WatchConnectivityService.shared.send(calibration: profile)
            if startsWorkout {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.beginTracking() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.screen = .home }
            }
        }
        calibrationModel.start()
    }

    /// Skip calibration and reuse the previous profile (or the default one).
    func useExistingCalibration() {
        calibrationModel.cancel()
        if case .calibration(let startsWorkout) = screen, startsWorkout {
            beginTracking()
        } else {
            screen = .home
        }
    }

    func cancelCalibration() {
        calibrationModel.cancel()
        if case .calibration(let startsWorkout) = screen, startsWorkout {
            session.end(save: false) {}
        }
        screen = .home
    }

    func beginTracking() {
        let wearing = CalibrationViewModel.currentWearing
        let profile = calibration ?? .defaultProfile(wrist: wearing.wrist, crownTowardsHand: wearing.crownTowardsHand)
        workout.begin(profile: profile)
        screen = .workout
    }

    func endWorkout() {
        workout.stop()
        let sets = workout.completedSets
        let record = WorkoutRecord(
            id: UUID(),
            startDate: session.startDate ?? sets.first?.startDate ?? Date(),
            endDate: Date(),
            sets: sets,
            averageHeartRate: session.averageHeartRate,
            activeEnergyKilocalories: session.activeEnergy > 0 ? session.activeEnergy : nil,
            calibratedAt: calibration?.createdAt
        )
        session.end(save: !sets.isEmpty) {}
        if !sets.isEmpty {
            WatchConnectivityService.shared.send(workout: record)
            screen = .summary(record)
        } else {
            screen = .home
        }
    }
}
