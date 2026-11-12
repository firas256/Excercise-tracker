import Foundation
import HealthKit
import WatchKit

/// Keeps the app running (and the sensors streaming) while the wrist is down during a workout.
///
/// Uses a HealthKit strength-training workout session (heart rate, calories, saved to the
/// Fitness app). If HealthKit is unavailable – e.g. no permission, or the HealthKit capability was
/// removed for a free Apple ID – it falls back to an extended runtime session.
final class WorkoutSessionService: NSObject, ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeEnergy: Double = 0
    @Published private(set) var isActive = false
    @Published private(set) var usingHealthKit = false
    @Published private(set) var startDate: Date?
    @Published var lastError: String?

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
        if healthAvailable {
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
                        self?.fallBackToRuntimeSession()
                    }
                }
                usingHealthKit = true
                return
            } catch {
                lastError = error.localizedDescription
            }
        }
        fallBackToRuntimeSession()
    }

    /// Ends the workout. When `save` is false the HealthKit workout is discarded.
    func end(save: Bool, completion: @escaping () -> Void) {
        guard isActive else { completion(); return }
        isActive = false
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

    private func fallBackToRuntimeSession() {
        session?.end()
        session = nil
        builder = nil
        usingHealthKit = false
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
        if toState == .ended {
            finishHealthKitWorkout(at: date)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
            if self.isActive { self.fallBackToRuntimeSession() } else { self.complete() }
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
