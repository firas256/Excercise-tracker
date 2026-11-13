import Foundation
import WatchConnectivity

/// Sends finished workouts, calibration info and optional training recordings to the iPhone.
///
/// Everything goes through an on-disk outbox first and is only handed to WatchConnectivity once
/// the session is activated (calling transfer APIs on an inactive session is a programmer error).
/// `transferUserInfo` / `transferFile` are then queued by the system and delivered even if the
/// phone is out of range right now, and nothing is lost if the app quits before activation.
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private let fileManager = FileManager.default
    private lazy var outbox: URL = {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Outbox", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var isActivated: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
    }

    /// True when the iPhone app can receive live messages right now.
    var isPhoneReachable: Bool { isActivated && WCSession.default.isReachable }

    /// Streams live calibration progress to the iPhone (best effort: dropped if not reachable).
    func sendLive(_ state: CalibrationLiveState) {
        guard isPhoneReachable, let data = PayloadCoding.encode(state) else { return }
        WCSession.default.sendMessage([SyncKeys.calibrationLive: data], replyHandler: nil, errorHandler: nil)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(workout: WorkoutRecord) {
        guard let data = PayloadCoding.encode(workout) else { return }
        try? data.write(to: outbox.appendingPathComponent("workout-\(workout.id.uuidString).json"), options: .atomic)
        flush()
    }

    func send(calibration: CalibrationProfile) {
        guard isActivated, let data = PayloadCoding.encode(CalibrationSummary(profile: calibration)) else { return }
        try? WCSession.default.updateApplicationContext([SyncKeys.calibration: data])
    }

    /// Writes the set's arm-frame samples as CSV (labelled with the confirmed exercise) and queues it.
    func sendTrainingRecording(samples: [ArmSample], label: ExerciseType, setID: UUID) {
        let base = "recording-\(setID.uuidString)"
        let csv = outbox.appendingPathComponent(base + ".csv")
        do {
            try TrainingCSV.make(samples).write(to: csv, atomically: true, encoding: .utf8)
            let meta = [SyncKeys.trainingLabel: label.rawValue, SyncKeys.trainingSetID: setID.uuidString]
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: outbox.appendingPathComponent(base + ".meta"), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: csv)
            return
        }
        flush()
    }

    /// Hands queued items to WatchConnectivity. Safe to call any time; does nothing until activated.
    func flush() {
        guard isActivated else { return }
        let session = WCSession.default
        let files = (try? fileManager.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        let inFlight = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for url in files {
            let name = url.lastPathComponent
            if name.hasPrefix("workout-"), url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url) {
                    session.transferUserInfo([SyncKeys.workout: data])
                }
                try? fileManager.removeItem(at: url)
            } else if name.hasPrefix("recording-"), url.pathExtension == "csv", !inFlight.contains(name) {
                let metaURL = url.deletingPathExtension().appendingPathExtension("meta")
                guard let metaData = try? Data(contentsOf: metaURL),
                      let meta = try? JSONDecoder().decode([String: String].self, from: metaData) else { continue }
                session.transferFile(url, metadata: meta)
            }
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            DispatchQueue.main.async { self.flush() }
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard error == nil else { return }  // stays in the outbox and is retried on the next flush
        let url = fileTransfer.file.fileURL
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
    }
}
