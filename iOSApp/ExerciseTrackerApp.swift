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
            .environmentObject(store)
            .environmentObject(connectivity)
            .environmentObject(health)
            .tint(.green)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Called when the watch app asks for Health access; the prompt is then shown on the phone.
    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        HKHealthStore().handleAuthorizationForExtension { _, _ in }
    }
}
