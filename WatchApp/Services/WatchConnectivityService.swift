import Foundation
import WatchConnectivity

/// Sends finished workouts, calibration info and optional training recordings to the iPhone.
/// `transferUserInfo` / `transferFile` are queued by the system and delivered even if the phone
/// is out of range right now.
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(workout: WorkoutRecord) {
        guard WCSession.isSupported(), let data = PayloadCoding.encode(workout) else { return }
        WCSession.default.transferUserInfo([SyncKeys.workout: data])
    }

    func send(calibration: CalibrationProfile) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = PayloadCoding.encode(CalibrationSummary(profile: calibration)) else { return }
        try? WCSession.default.updateApplicationContext([SyncKeys.calibration: data])
    }

    /// Writes the set's arm-frame samples as CSV and queues it for the phone.
    func sendTrainingRecording(samples: [ArmSample], label: ExerciseType, setID: UUID) {
        guard WCSession.isSupported() else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(setID.uuidString).csv")
        do {
            try TrainingCSV.make(samples).write(to: url, atomically: true, encoding: .utf8)
            WCSession.default.transferFile(url, metadata: [
                SyncKeys.trainingLabel: label.rawValue,
                SyncKeys.trainingSetID: setID.uuidString,
            ])
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
    }
}
