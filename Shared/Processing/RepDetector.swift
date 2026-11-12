import Foundation

/// Index boundaries of one repetition inside a set buffer.
struct RepSegment: Equatable, Sendable {
    /// Resting-side extreme before the rep (range of motion is measured from here).
    var start: Int
    /// Turnaround extreme (furthest from the resting position).
    var peak: Int
    /// Resting-side extreme after the rep.
    var end: Int
    /// Timing indices from velocity thresholds, so pauses are not counted as movement:
    /// the "away" phase runs moveStart...awayEnd, the "return" phase returnStart...moveEnd.
    var moveStart: Int
    var awayEnd: Int
    var returnStart: Int
    var moveEnd: Int
}

struct RepDetectionResult: Sendable {
    var signal: RepSignalKind
    /// Smoothed signal the reps were segmented on.
    var series: [Double]
    /// Seconds per rep estimated from autocorrelation.
    var period: Double
    /// 0...1 – how periodic the movement looks.
    var periodicity: Double
    var segments: [RepSegment]
    /// True when the resting position is the signal's high side (e.g. squat on the vertical signal).
    var restHigh: Bool
}

extension ExerciseType {
    /// Signal that best captures this exercise's repetitions.
    var preferredSignal: RepSignalKind {
        switch self {
        case .bicepCurl, .hammerCurl, .lateralRaise, .frontRaise, .uprightRow, .chestFly,
             .overheadTricepsExtension, .skullCrusher, .kettlebellSwing, .tricepsPushdown, .pushUp:
            return .elevation
        case .pecDeck:
            return .rotation
        case .seatedCableRow, .chestPressMachine:
            return .forearm
        case .shoulderPress, .shrug, .benchPress, .bentOverRow, .deadlift, .romanianDeadlift, .squat,
             .gobletSquat, .lunge, .latPulldown, .legPress, .legExtension, .legCurl, .pullUp, .dip:
            return .vertical
        }
    }
}

/// Finds repetitions in a buffer of motion.
///
/// 1. Several candidate signals are derived (forearm angle, rotation, vertical and forearm travel).
/// 2. The most periodic one (autocorrelation) with enough amplitude is chosen.
/// 3. Reps are segmented with a hysteresis state machine on a locally normalised version of it,
///    which tolerates slow drift, changing tempo and pauses at the top or bottom.
enum RepDetector {

    static func minimumAmplitude(_ kind: RepSignalKind) -> Double {
        switch kind {
        case .elevation: return 15   // degrees
        case .rotation: return 20    // degrees
        case .vertical: return 7     // cm (leaky-integrated, so a little under the true value)
        case .forearm: return 7      // cm
        }
    }

    /// - Parameters:
    ///   - preferred: Signal to use when the exercise is known.
    ///   - sensitivity: < 1 lowers amplitude thresholds (used for exercises where the wrist barely moves).
    static func detect(_ signals: MotionSignals, preferred: RepSignalKind? = nil, sensitivity: Double = 1) -> RepDetectionResult? {
        let n = signals.count
        guard n > 20 else { return nil }
        let rate = 1 / signals.dt
        let smoothWindow = max(3, Int(0.14 * rate) | 1)
        let minLag = Int(0.6 * rate)
        let maxLag = Int(8 * rate)
        let windowLength = min(n, Int(16 * rate))

        struct Candidate {
            var kind: RepSignalKind
            var smooth: [Double]
            var lag: Int
            var score: Double
        }
        var candidates: [Candidate] = []
        for kind in [RepSignalKind.elevation, .rotation, .vertical, .forearm] {
            let smooth = SignalMath.movingAverage(signals.series(kind), window: smoothWindow)
            let window = Array(smooth[(n - windowLength)...])
            let amplitude = SignalMath.percentile(window, 95) - SignalMath.percentile(window, 5)
            guard amplitude >= minimumAmplitude(kind) * sensitivity else { continue }
            guard let p = SignalMath.dominantPeriod(window, minLag: minLag, maxLag: maxLag) else { continue }
            candidates.append(Candidate(kind: kind, smooth: smooth, lag: p.lag, score: p.score))
        }
        guard !candidates.isEmpty else { return nil }

        // Gravity-based elevation never drifts, so prefer it when it is nearly as periodic as the best.
        func adjusted(_ c: Candidate) -> Double {
            switch c.kind {
            case .elevation: return c.score + 0.12
            case .vertical: return c.score + 0.03
            default: return c.score
            }
        }
        var chosen = candidates.max(by: { adjusted($0) < adjusted($1) })!
        if let preferred, let p = candidates.first(where: { $0.kind == preferred }), p.score >= 0.25 {
            chosen = p
        }
        guard chosen.score >= 0.3 || (preferred != nil && chosen.kind == preferred && chosen.score >= 0.25) else { return nil }

        let minAmp = minimumAmplitude(chosen.kind) * sensitivity
        let (segments, restHigh) = segment(chosen.smooth, period: chosen.lag, minAmplitude: minAmp, signals: signals, kind: chosen.kind)
        return RepDetectionResult(
            signal: chosen.kind,
            series: chosen.smooth,
            period: Double(chosen.lag) * signals.dt,
            periodicity: chosen.score,
            segments: segments,
            restHigh: restHigh
        )
    }

    /// Hysteresis segmentation on a locally normalised signal.
    static func segment(_ x: [Double], period: Int, minAmplitude: Double, signals: MotionSignals, kind: RepSignalKind) -> ([RepSegment], Bool) {
        let n = x.count
        guard n > 4 else { return ([], false) }
        let env = SignalMath.rollingExtrema(x, halfWidth: max(5, Int(1.25 * Double(period))))
        var z = [Double](repeating: 0, count: n)
        var valid = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let span = env.max[i] - env.min[i]
            if span >= minAmplitude {
                z[i] = (x[i] - env.min[i]) / span
                valid[i] = true
            }
        }

        let restHigh = restingSideIsHigh(signals.rawSeries(kind), period: period)
        if restHigh { for i in 0..<n where valid[i] { z[i] = 1 - z[i] } }

        let up = 0.5
        let down = 0.3

        // Pass 1: find (rest extreme before, turnaround extreme, down-crossing) triples.
        var raw: [(start: Int, peak: Int, down: Int)] = []
        var inRest = true
        var startIdx = 0
        var peakIdx = 0
        for i in 0..<n {
            guard valid[i] else {
                if inRest { startIdx = i }
                continue
            }
            if inRest {
                if !valid[startIdx] || z[i] <= z[startIdx] { startIdx = i }
                if z[i] > up {
                    inRest = false
                    peakIdx = i
                }
            } else {
                if z[i] > z[peakIdx] { peakIdx = i }
                if z[i] < down {
                    raw.append((startIdx, peakIdx, i))
                    inRest = true
                    startIdx = i
                }
            }
        }
        guard !raw.isEmpty else { return ([], restHigh) }

        // Velocity of the (smoothed) signal for phase timing.
        var v = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) { v[i] = (x[i + 1] - x[i - 1]) / 2 }

        func phase(_ a: Int, _ b: Int) -> (Int, Int) {
            guard b > a + 1 else { return (a, b) }
            var iMax = a
            for i in a...b where abs(v[i]) > abs(v[iMax]) { iMax = i }
            let limit = 0.1 * abs(v[iMax])
            var s = iMax
            while s > a && abs(v[s]) >= limit { s -= 1 }
            var e = iMax
            while e < b && abs(v[e]) >= limit { e += 1 }
            return (s, e)
        }

        // Pass 2: end extreme of each rep (lowest point before the next rep starts), then timing.
        var segments: [RepSegment] = []
        for (k, r) in raw.enumerated() {
            let searchEnd = k + 1 < raw.count ? raw[k + 1].start : min(n - 1, r.down + max(2, period / 2))
            var endMin = r.down
            if searchEnd > r.down {
                for j in r.down...searchEnd where valid[j] && z[j] < z[endMin] { endMin = j }
            }
            let away = phase(r.start, r.peak)
            let back = phase(r.peak, endMin)
            segments.append(RepSegment(start: r.start, peak: r.peak, end: max(endMin, r.peak),
                                       moveStart: away.0, awayEnd: away.1, returnStart: back.0, moveEnd: back.1))
        }

        // Pass 3: discard tiny wiggles and implausibly short reps.
        let amps = segments.map { signals.range(kind, from: $0.start, to: $0.peak) }
        let medianAmp = SignalMath.median(amps)
        let minDuration = Int(0.4 / signals.dt)
        var filtered: [RepSegment] = []
        for (seg, amp) in zip(segments, amps) {
            if seg.moveEnd - seg.moveStart < minDuration { continue }
            if amp < max(minAmplitude * 0.8, 0.35 * medianAmp) { continue }
            filtered.append(seg)
        }
        return (filtered, restHigh)
    }

    /// The buffer starts at rest (pre-roll), so the direction of the first big excursion tells us
    /// which side of the signal is the resting position: moving up first ⇒ resting low.
    static func restingSideIsHigh(_ raw: [Double], period: Int) -> Bool {
        // Only look at the first couple of reps so integration drift cannot matter.
        let head = max(2, min(raw.count / 6, period / 4))
        let x = Array(raw.prefix(head + 2 * period))
        let n = x.count
        guard n > head + 2 else { return false }
        let range = (x.max() ?? 0) - (x.min() ?? 0)
        guard range > 0 else { return false }
        let base = SignalMath.mean(Array(x[0..<head]))
        for i in head..<n where abs(x[i] - base) > 0.35 * range {
            return x[i] < base
        }
        return false
    }
}
