import Foundation

/// Orientation-independent description of a set, computed in the calibrated arm frame.
/// This is the input of the exercise classifier.
struct MotionFeatures: Codable, Equatable, Hashable, Sendable {
    /// Median forearm elevation (deg) at the starting position of each rep.
    var startElevation: Double
    /// Median forearm elevation (deg) at the turnaround point of each rep.
    var peakElevation: Double
    /// Mean cos(roll) while the forearm is roughly horizontal: +1 palm down, -1 palm up. nil if unknown.
    var palmDown: Double?
    /// |mean sin(roll)| while the forearm is roughly horizontal: 1 = thumb up (neutral grip). nil if unknown.
    var thumbUp: Double?
    /// Dominant rotation axis in arm frame (absolute components). nil when there is little rotation.
    var axisTwist: Double?
    var axisPalm: Double?
    var axisRadial: Double?
    /// Median per-rep rotation about the dominant axis (deg).
    var rotationAmplitude: Double
    /// Median per-rep rotation about world vertical (deg).
    var yawAmplitude: Double
    /// Median per-rep vertical hand travel (cm).
    var verticalAmplitude: Double
    /// Median per-rep hand travel along the forearm (cm).
    var forearmAmplitude: Double
    /// Fraction of reps that start at the high point (0 = start low like a curl, 1 = start high like a squat).
    var startsHigh: Double
    /// Average direction of hand travel along the forearm from start to turnaround: +1 push, -1 pull.
    var pushDirection: Double
    /// Seconds per rep.
    var repPeriod: Double
    /// Which way the effortful (faster) half of each rep goes: > 0 rising is quicker (curls, raises,
    /// presses), < 0 lowering is quicker (pushdowns, pulldowns). nil when it can't be told.
    var upTempoBias: Double? = nil
    /// Radius (cm) the watch swings on: vertical travel ÷ change in sin(forearm angle). About the
    /// forearm length when only the elbow moves (curls, pushdowns), the whole arm when the shoulder
    /// moves (raises). nil when the forearm angle barely changes.
    var pivotRadius: Double? = nil

    /// Lowest / highest forearm angle of a rep, whichever end the rep happened to start from.
    var lowElevation: Double { min(startElevation, peakElevation) }
    var highElevation: Double { max(startElevation, peakElevation) }

    enum Key: String, CaseIterable, Codable, Sendable {
        case startElevation, peakElevation, palmDown, thumbUp, axisTwist, axisPalm, axisRadial
        case rotationAmplitude, yawAmplitude, verticalAmplitude, forearmAmplitude
        case startsHigh, pushDirection, repPeriod
        case lowElevation, highElevation, upTempoBias, pivotRadius
    }

    func value(_ key: Key) -> Double? {
        switch key {
        case .lowElevation: return lowElevation
        case .highElevation: return highElevation
        case .upTempoBias: return upTempoBias
        case .pivotRadius: return pivotRadius
        case .startElevation: return startElevation
        case .peakElevation: return peakElevation
        case .palmDown: return palmDown
        case .thumbUp: return thumbUp
        case .axisTwist: return axisTwist
        case .axisPalm: return axisPalm
        case .axisRadial: return axisRadial
        case .rotationAmplitude: return rotationAmplitude
        case .yawAmplitude: return yawAmplitude
        case .verticalAmplitude: return verticalAmplitude
        case .forearmAmplitude: return forearmAmplitude
        case .startsHigh: return startsHigh
        case .pushDirection: return pushDirection
        case .repPeriod: return repPeriod
        }
    }
}
