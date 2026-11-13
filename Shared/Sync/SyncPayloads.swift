import Foundation

/// Keys and helpers shared by the watch and phone WatchConnectivity code.
enum SyncKeys {
    static let workout = "workout"
    static let calibration = "calibration"
    static let trainingLabel = "trainingLabel"
    static let trainingSetID = "trainingSetID"
    static let relabel = "relabel"
    static let calibrationLive = "calibrationLive"
}

/// Live calibration progress the watch streams to the iPhone, so the instructions can be followed
/// on the phone's big screen (and spoken) while the arm is raised and the watch can't be read.
struct CalibrationLiveState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case moveIntoPosition
        case holdStill
        case holding
        case wrongPose
        case finished
        case cancelled
    }

    var step: Int
    var totalSteps: Int
    var pose: CalibrationPose
    var status: Status
    /// Hold progress 0...1 while `status == .holding`.
    var progress: Double
    /// Correction shown when `status == .wrongPose`.
    var message: String?

    init(step: Int, pose: CalibrationPose, phase: CalibrationPhase) {
        self.step = step
        self.totalSteps = CalibrationPose.allCases.count
        self.pose = pose
        self.progress = 0
        self.message = nil
        switch phase {
        case .waitingForMovement: status = .moveIntoPosition
        case .waitingForStillness: status = .holdStill
        case .holding(let p):
            status = .holding
            progress = p
        case .wrongPose(let m):
            status = .wrongPose
            message = m
        case .finished:
            status = .finished
            progress = 1
        }
    }

    static func cancelled(step: Int, pose: CalibrationPose) -> CalibrationLiveState {
        var s = CalibrationLiveState(step: step, pose: pose, phase: .waitingForMovement)
        s.status = .cancelled
        return s
    }

    /// True when the phone should be told about `new` (status/step change, or a hold-progress quarter).
    static func isWorthSending(_ new: CalibrationLiveState, after old: CalibrationLiveState?) -> Bool {
        guard let old else { return true }
        if old.status != new.status || old.step != new.step || old.message != new.message { return true }
        return (new.progress * 4).rounded(.down) != (old.progress * 4).rounded(.down)
    }
}

/// Calibration info the watch shares with the phone (for display only).
struct CalibrationSummary: Codable, Equatable, Sendable {
    var date: Date
    var wrist: WristSide
    var overheadElevation: Double
    var supinationRange: Double

    init(profile: CalibrationProfile) {
        date = profile.createdAt
        wrist = profile.wrist
        overheadElevation = profile.overheadElevation
        supinationRange = profile.supinationRange
    }
}

enum PayloadCoding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder().decode(type, from: data)
    }
}

/// CSV format for exported sensor recordings. Columns are in the calibrated arm frame, so a model
/// trained on them works no matter which wrist the watch is worn on. Compatible with Create ML's
/// Activity Classifier (one folder per exercise, one file per set).
enum TrainingCSV {
    static let columns = [
        "timestamp",
        "gravity_forearm", "gravity_palm", "gravity_radial",
        "accel_forearm", "accel_palm", "accel_radial",
        "rotation_forearm", "rotation_palm", "rotation_radial",
    ]

    /// Feature columns (everything except the timestamp).
    static var featureColumns: [String] { Array(columns.dropFirst()) }

    static func values(of s: ArmSample) -> [Double] {
        [s.gravity.x, s.gravity.y, s.gravity.z,
         s.acceleration.x, s.acceleration.y, s.acceleration.z,
         s.rotation.x, s.rotation.y, s.rotation.z]
    }

    static func make(_ samples: [ArmSample]) -> String {
        var out = columns.joined(separator: ",") + "\n"
        out.reserveCapacity(samples.count * 90)
        let t0 = samples.first?.t ?? 0
        for s in samples {
            let row = [s.t - t0] + values(of: s)
            out += row.map { String(format: "%.4f", $0) }.joined(separator: ",") + "\n"
        }
        return out
    }

    static func parse(_ csv: String) -> [ArmSample] {
        var result: [ArmSample] = []
        for line in csv.split(separator: "\n").dropFirst() {
            let v = line.split(separator: ",").compactMap { Double($0) }
            guard v.count == 10 else { continue }
            result.append(ArmSample(t: v[0], gravity: Vector3(v[1], v[2], v[3]),
                                    acceleration: Vector3(v[4], v[5], v[6]), rotation: Vector3(v[7], v[8], v[9])))
        }
        return result
    }
}
