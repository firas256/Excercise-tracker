import Foundation
import WatchConnectivity

/// Receives workouts, calibration info and training recordings from the watch.
final class PhoneConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isSupported = WCSession.isSupported()
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    /// Live calibration running on the watch (nil when none). Drives the full-screen guide.
    @Published var liveCalibration: CalibrationLiveState?

    private let store: WorkoutStore

    init(store: WorkoutStore) {
        self.store = store
        super.init()
        activate()
        // `-demoCalibration YES` launch argument: show the calibration guide (Simulator / screenshots).
        if UserDefaults.standard.bool(forKey: "demoCalibration") {
            liveCalibration = CalibrationLiveState(step: 1, pose: .armForward, phase: .holding(0.6))
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    private func refreshState(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isPaired = paired
            self.isWatchAppInstalled = installed
            self.isReachable = reachable
        }
    }

    private func handle(context: [String: Any]) {
        if let data = context[SyncKeys.calibration] as? Data,
           let summary = PayloadCoding.decode(CalibrationSummary.self, from: data) {
            DispatchQueue.main.async { self.store.setCalibration(summary) }
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refreshState(session)
        handle(context: session.receivedApplicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after switching to a different watch.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) { refreshState(session) }

    func sessionReachabilityDidChange(_ session: WCSession) { refreshState(session) }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[SyncKeys.workout] as? Data,
           let workout = PayloadCoding.decode(WorkoutRecord.self, from: data) {
            DispatchQueue.main.async { self.store.add(workout) }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[SyncKeys.calibrationLive] as? Data,
              let state = PayloadCoding.decode(CalibrationLiveState.self, from: data) else { return }
        DispatchQueue.main.async {
            switch state.status {
            case .cancelled:
                self.liveCalibration = nil
            case .finished:
                self.liveCalibration = state
                // Leave "Calibrated!" up for a moment, then get out of the way.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.liveCalibration?.status == .finished { self.liveCalibration = nil }
                }
            default:
                self.liveCalibration = state
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(context: applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so move it synchronously.
        let label = file.metadata?[SyncKeys.trainingLabel] as? String ?? "unlabeled"
        let setID = file.metadata?[SyncKeys.trainingSetID] as? String ?? UUID().uuidString
        store.storeTrainingFile(at: file.fileURL, label: label, setID: setID)
    }
}
