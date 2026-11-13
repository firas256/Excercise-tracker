import Foundation
import HealthKit

/// Requests Health access from the phone (the watch app shares the same authorization).
final class HealthPermissionService: ObservableObject {
    enum Status: Equatable {
        case unknown
        case notRequested
        case requested
        case unavailable
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var lastError: String?

    private let healthStore = HKHealthStore()

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    init() { refresh() }

    func refresh() {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        healthStore.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { result, _ in
            DispatchQueue.main.async {
                switch result {
                case .unnecessary: self.status = .requested
                case .shouldRequest: self.status = .notRequested
                default: self.status = .unknown
                }
            }
        }
    }

    /// Opens Rep Coach on the paired Apple Watch and starts a workout there (calibration first).
    /// Uses HealthKit's workout launch, so it works even when the watch app isn't open.
    func startWorkoutOnWatch(completion: @escaping (String?) -> Void) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        healthStore.startWatchApp(with: configuration) { success, error in
            DispatchQueue.main.async {
                completion(success ? nil : (error?.localizedDescription ?? "Couldn't reach the watch."))
            }
        }
    }

    func request(completion: (() -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            completion?()
            return
        }
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { _, error in
            DispatchQueue.main.async {
                self.lastError = error?.localizedDescription
                self.refresh()
                completion?()
            }
        }
    }
}
