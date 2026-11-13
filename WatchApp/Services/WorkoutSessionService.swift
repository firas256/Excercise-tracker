import Foundation
import HealthKit
import WatchKit

/// Keeps the app running (and the sensors streaming) while the wrist is down during a workout.
///
/// Uses a HealthKit strength-training workout session (heart rate, calories, saved to the
/// Fitness app). Only a *running* workout session lets a watch app play haptics and message the
/// iPhone once the wrist is lowered (watchOS treats the app as backgrounded then, even though its
/// dimmed screen is still showing). If HealthKit can't be used – no permission, or the HealthKit
/// capability was removed for a free Apple ID – it falls back to an extended runtime session, which
/// keeps the sensors running but nothing else; `backgroundIssue` then says why, for the UI.
final class WorkoutSessionService: NSObject, ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeEnergy: Double = 0
    @Published private(set) var isActive = false
    @Published private(set) var usingHealthKit = false
    @Published private(set) var startDate: Date?
    @Published var lastError: String?
    /// True once the HealthKit workout session is running: haptics and live updates to the phone
    /// then keep working with the wrist down.
    @Published private(set) var isWorkoutSessionRunning = false
    /// Why haptics and phone updates will pause when the wrist is down (nil = no problem).
    @Published private(set) var backgroundIssue: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var runtimeSession: WKExtendedRuntimeSession?
    private var heartRateSum = 0.0
    private var heartRateCount = 0
    private var endCompletion: (() -> Void)?
    private var saveOnEnd = true

    var averageHeartRate: Double? {
        heartRateCount > 0 ? heartRateSum / Double(heartRateCount) : nil
    }

    static var typesToShare: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    static var typesToRead: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    var healthAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard healthAvailable else { completion(false); return }
        healthStore.requestAuthorization(toShare: Self.typesToShare, read: Self.typesToRead) { success, error in
            DispatchQueue.main.async {
                if let error { self.lastError = error.localizedDescription }
                completion(success)
            }
        }
    }

    func start() {
        guard !isActive else { return }
        heartRateSum = 0
        heartRateCount = 0
        heartRate = nil
        activeEnergy = 0
        startDate = Date()
        isActive = true
        isWorkoutSessionRunning = false
        backgroundIssue = nil
        guard healthAvailable else {
            fallBackToRuntimeSession(reason: "Health isn't available on this watch.")
            return
        }
        // Ask for Health access first if it was never asked (e.g. "Not Now" at first launch, or a
        // workout started from the iPhone) – without it the workout session can't run.
        // (`-skipHealthPrompt YES`: UI tests, where a system sheet would cover the screen.)
        if healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .notDetermined,
           !UserDefaults.standard.bool(forKey: "skipHealthPrompt") {
            healthStore.requestAuthorization(toShare: Self.typesToShare, read: Self.typesToRead) { _, error in
                DispatchQueue.main.async {
                    if let error { self.lastError = error.localizedDescription }
                    guard self.isActive, self.session == nil, self.runtimeSession == nil else { return }
                    self.startHealthKitSession()
                }
            }
            return
        }
        startHealthKitSession()
    }

    private func startHealthKitSession() {
        if healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied {
            fallBackToRuntimeSession(reason: Self.deniedMessage)
            return
        }
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] success, error in
                guard !success else { return }
                DispatchQueue.main.async {
                    self?.lastError = error?.localizedDescription
                    self?.fallBackToRuntimeSession(reason: Self.failureMessage(error))
                }
            }
            usingHealthKit = true
        } catch {
            lastError = error.localizedDescription
            fallBackToRuntimeSession(reason: Self.failureMessage(error))
        }
    }

    static let deniedMessage = "Health access for workouts is off. Turn it on: iPhone Settings › Privacy & Security › Health › Rep Coach (allow Workouts)."

    static func failureMessage(_ error: Error?) -> String {
        let detail = error?.localizedDescription ?? "unknown error"
        if detail.localizedCaseInsensitiveContains("entitlement") {
            return "This build has no HealthKit (it was removed for a free Apple ID), so the watch can't run a workout session."
        }
        return "The workout session couldn't start (\(detail))."
    }

    /// Ends the workout. When `save` is false the HealthKit workout is discarded.
    func end(save: Bool, completion: @escaping () -> Void) {
        guard isActive else { completion(); return }
        isActive = false
        isWorkoutSessionRunning = false
        backgroundIssue = nil
        if let session {
            saveOnEnd = save
            endCompletion = completion
            session.end()
        } else {
            runtimeSession?.invalidate()
            runtimeSession = nil
            completion()
        }
    }

    private func fallBackToRuntimeSession(reason: String) {
        session?.end()
        session = nil
        builder = nil
        usingHealthKit = false
        isWorkoutSessionRunning = false
        backgroundIssue = reason
        guard runtimeSession == nil else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        runtimeSession = s
    }

    private func finishHealthKitWorkout(at date: Date) {
        guard let builder else { complete(); return }
        builder.endCollection(withEnd: date) { [weak self] _, _ in
            guard let self else { return }
            if self.saveOnEnd {
                builder.finishWorkout { _, error in
                    if let error { DispatchQueue.main.async { self.lastError = error.localizedDescription } }
                    self.complete()
                }
            } else {
                builder.discardWorkout()
                self.complete()
            }
        }
    }

    private func complete() {
        DispatchQueue.main.async {
            self.session = nil
            self.builder = nil
            let c = self.endCompletion
            self.endCompletion = nil
            c?()
        }
    }
}

extension WorkoutSessionService: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .running {
            DispatchQueue.main.async {
                guard self.session === workoutSession else { return }
                self.isWorkoutSessionRunning = true
                self.backgroundIssue = nil
            }
        }
        if toState == .ended {
            finishHealthKitWorkout(at: date)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            if self.isActive {
                self.fallBackToRuntimeSession(reason: Self.failureMessage(error))
            } else {
                self.complete()
            }
        }
    }
}

extension WorkoutSessionService: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        var hr: Double?
        var kcal: Double?
        if collectedTypes.contains(hrType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            hr = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?.doubleValue(for: unit)
        }
        if collectedTypes.contains(energyType) {
            kcal = workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        DispatchQueue.main.async {
            if let hr {
                self.heartRate = hr
                self.heartRateSum += hr
                self.heartRateCount += 1
            }
            if let kcal { self.activeEnergy = kcal }
        }
    }
}

extension WorkoutSessionService: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        DispatchQueue.main.async {
            if let error { self.lastError = error.localizedDescription }
            if self.runtimeSession === extendedRuntimeSession { self.runtimeSession = nil }
        }
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}
