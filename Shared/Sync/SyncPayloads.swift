import Foundation

/// Keys and helpers shared by the watch and phone WatchConnectivity code.
enum SyncKeys {
    static let workout = "workout"
    static let calibration = "calibration"
    static let trainingLabel = "trainingLabel"
    static let trainingSetID = "trainingSetID"
    static let relabel = "relabel"
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
