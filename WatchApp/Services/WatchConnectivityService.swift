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

    /// Buttons pressed on the iPhone during a workout.
    var onCommand: ((WatchCommand) -> Void)?
    /// The live link to the phone came back (or dropped): resend the current state.
    var onReachabilityChange: ((Bool) -> Void)?

    /// When the newest state of each live key was handed over (main thread only), so a late
    /// failure of an older message never replaces a newer state.
    private var latestStamp: [String: Double] = [:]

    /// Returns false only if the session isn't activated yet (nothing could be queued).
    @discardableResult
    func sendLiveWorkout(_ state: LiveWorkoutState) -> Bool {
        guard let data = PayloadCoding.encode(state) else { return false }
        return sendLatest(SyncKeys.liveWorkout, data)
    }

    /// Arm-motion frames for the phone's 3-D view (live only; dropped when the phone can't be
    /// reached). Safe to call from any queue.
    func sendFrames(_ frames: [MotionFrame]) {
        guard isPhoneReachable, let data = PayloadCoding.encode(frames) else { return }
        WCSession.default.sendMessage([SyncKeys.motionFrames: data], replyHandler: nil, errorHandler: nil)
    }

    /// Streams live calibration progress to the iPhone.
    @discardableResult
    func sendLive(_ state: CalibrationLiveState) -> Bool {
        guard let data = PayloadCoding.encode(state) else { return false }
        return sendLatest(SyncKeys.calibrationLive, data)
    }

    /// Delivers the newest state for `key`: as a live message when the phone is reachable, and
    /// otherwise – or if that message fails – as a queued transfer, which the system delivers as
    /// soon as it can, even while this app is suspended. Only the newest queued state per key is
    /// kept, and every payload is time-stamped so the phone can ignore anything older than what it
    /// already has.
    private func sendLatest(_ key: String, _ data: Data) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { _ = self.sendLatest(key, data) }
            return isActivated
        }
        guard isActivated else { return false }
        let stamp = Date().timeIntervalSince1970
        latestStamp[key] = stamp
        let payload: [String: Any] = [key: data, SyncKeys.sentAt: stamp]
        cancelQueued(key)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.latestStamp[key] == stamp else { return }  // superseded
                    self.cancelQueued(key)
                    WCSession.default.transferUserInfo(payload)
                }
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
        return true
    }

    private func cancelQueued(_ key: String) {
        for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.userInfo[key] != nil {
            transfer.cancel()
        }
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

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[SyncKeys.command] as? Data,
              let command = PayloadCoding.decode(WatchCommand.self, from: data) else { return }
        DispatchQueue.main.async { self.onCommand?(command) }
    }

    /// Commands the phone queued while the watch couldn't be reached live.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[SyncKeys.command] as? Data,
              let command = PayloadCoding.decode(WatchCommand.self, from: data) else { return }
        let age = Date().timeIntervalSince1970 - (userInfo[SyncKeys.sentAt] as? Double ?? 0)
        guard age < command.maxQueuedAge else { return }  // too late to still mean the same thing
        DispatchQueue.main.async { self.onCommand?(command) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.onReachabilityChange?(reachable) }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard error == nil else { return }  // stays in the outbox and is retried on the next flush
        let url = fileTransfer.file.fileURL
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
    }
}
