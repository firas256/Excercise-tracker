import HealthKit
import SwiftUI
import UIKit

@main
struct ExerciseTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: WorkoutStore
    @StateObject private var connectivity: PhoneConnectivityService
    @StateObject private var health = HealthPermissionService()
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase

    /// `-forceColorScheme dark|light` (UI tests): render in that appearance whatever the device uses.
    private static let forcedColorScheme: ColorScheme? = {
        switch UserDefaults.standard.string(forKey: "forceColorScheme") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }()

    init() {
        // `-resetOnboarding` (UI tests): start from the first-launch experience.
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "onboardingComplete")
        }
        let store = WorkoutStore()
        _store = StateObject(wrappedValue: store)
        _connectivity = StateObject(wrappedValue: PhoneConnectivityService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    ContentView()
                } else {
                    OnboardingView { onboardingComplete = true }
                }
            }
            // Calibration steps and the live workout run on the watch but are followed here,
            // so the user never has to turn their wrist mid-set.
            .fullScreenCover(isPresented: Binding(
                get: { connectivity.liveCalibration != nil || (connectivity.liveWorkout != nil && !connectivity.liveWorkoutMinimized) },
                set: { shown in
                    guard !shown else { return }
                    if connectivity.liveCalibration != nil {
                        connectivity.liveCalibration = nil
                    } else {
                        connectivity.liveWorkoutMinimized = true
                    }
                }
            )) {
                Group {
                    if connectivity.liveCalibration != nil {
                        CalibrationGuideView()
                    } else {
                        LiveWorkoutView()
                    }
                }
                .environmentObject(connectivity)
                .environmentObject(store)
                .tint(Color.brand)
                .preferredColorScheme(Self.forcedColorScheme)
            }
            .environmentObject(store)
            .environmentObject(connectivity)
            .environmentObject(health)
            .tint(Color.brand)
            .preferredColorScheme(Self.forcedColorScheme)
            .onChange(of: scenePhase) { _, phase in
                // Messages from the watch are missed while the app is in the background.
                if phase == .active { connectivity.refreshLiveWorkout() }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Called when the watch app asks for Health access; the prompt is then shown on the phone.
    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        HKHealthStore().handleAuthorizationForExtension { _, _ in }
    }
}
