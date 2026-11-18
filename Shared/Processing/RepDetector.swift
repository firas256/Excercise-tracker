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
             .overheadTricepsExtension, .skullCrusher, .kettlebellSwing, .tricepsPushdown, .pushUp,
             .tricepsKickback, .reverseFly, .jumpingJacks:
            return .elevation
        case .pecDeck, .russianTwist:
            return .rotation
        case .seatedCableRow, .chestPressMachine:
            return .forearm
        case .shoulderPress, .shrug, .benchPress, .bentOverRow, .deadlift, .romanianDeadlift, .squat,
             .gobletSquat, .lunge, .latPulldown, .legPress, .legExtension, .legCurl, .pullUp, .dip,
             .sitUp, .burpee:
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

        // Which end of the movement is the resting one. Travel signals are double-integrated
        // acceleration: the raw sum drifts by tens of cm within seconds, so the drift-corrected
        // series is used for them (on 20 random variations of every simulated exercise: wrong 2 % of
        // the time instead of 28 %).
        let guess: Bool
        switch kind {
        case .vertical, .forearm: guess = restingSideIsHigh(signals.series(kind), period: period)
        case .elevation, .rotation: guess = restingSideIsHigh(signals.rawSeries(kind), period: period)
        }
        // Taking the wrong end as rest always loses a rep (the first or last cycle is never
        // completed – for travel signals, a last rep that only the series' bent tail completes is
        // dropped) and never adds one, so segment both ways and keep the one with more reps.
        let guessed = segmentReps(z, valid: valid, restHigh: guess, x: x, period: period,
                                  minAmplitude: minAmplitude, signals: signals, kind: kind)
        let other = segmentReps(z, valid: valid, restHigh: !guess, x: x, period: period,
                                minAmplitude: minAmplitude, signals: signals, kind: kind)
        return other.count > guessed.count ? (other, !guess) : (guessed, guess)
    }

    private static func segmentReps(_ normalised: [Double], valid: [Bool], restHigh: Bool, x: [Double], period: Int,
                                    minAmplitude: Double, signals: MotionSignals, kind: RepSignalKind) -> [RepSegment] {
        let n = normalised.count
        var z = normalised
        if restHigh { for i in 0..<n where valid[i] { z[i] = 1 - z[i] } }

        let up = 0.5
        let down = 0.3

        // Pass 1: find each rep's rest extreme before it, up-crossing, turnaround extreme and
        // down-crossing (nil: it hadn't come back by the end of the buffer).
        struct Raw { var start: Int; var up: Int; var peak: Int; var down: Int? }
        var raw: [Raw] = []
        var inRest = true
        var startIdx = 0
        var upIdx = 0
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
                    upIdx = i
                    peakIdx = i
                }
            } else {
                if z[i] > z[peakIdx] { peakIdx = i }
                if z[i] < down {
                    raw.append(Raw(start: startIdx, up: upIdx, peak: peakIdx, down: i))
                    inRest = true
                    startIdx = i
                }
            }
        }
        // Travel signals are bent near the ends of the buffer (see below), which can keep the last
        // rep's return from reaching the threshold: let the hand's real path decide that one.
        let travel = kind == .vertical || kind == .forearm
        if travel && !inRest {
            raw.append(Raw(start: startIdx, up: upIdx, peak: peakIdx, down: nil))
        }
        guard !raw.isEmpty else { return [] }

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

        // Rest extreme after each rep: the lowest point before the next rep starts.
        func restAfter(_ k: Int, from d: Int) -> Int {
            let searchEnd = k + 1 < raw.count ? raw[k + 1].start : min(n - 1, d + max(2, period / 2))
            var endMin = d
            if searchEnd > d {
                for j in d...searchEnd where valid[j] && z[j] < z[endMin] { endMin = j }
            }
            return endMin
        }
        let ends = raw.enumerated().map { k, r in r.down.map { restAfter(k, from: $0) } }

        // Pass 2: timing of each rep.
        func makeSegment(_ start: Int, _ peak: Int, _ end: Int) -> RepSegment {
            let away = phase(start, peak)
            let back = phase(peak, end)
            return RepSegment(start: start, peak: peak, end: max(end, peak),
                              moveStart: away.0, awayEnd: away.1, returnStart: back.0, moveEnd: back.1)
        }
        var segments: [RepSegment?] = raw.indices.map { k in ends[k].map { makeSegment(raw[k].start, raw[k].peak, $0) } }

        // Pass 3 criteria: not a tiny wiggle, not implausibly short.
        let minDuration = Int(0.4 / signals.dt)
        func amplitude(_ s: RepSegment) -> Double { signals.range(kind, from: s.start, to: s.peak) }
        let medianAmp = SignalMath.median(segments.compactMap { $0 }.map(amplitude))
        func isRep(_ s: RepSegment) -> Bool {
            s.moveEnd - s.moveStart >= minDuration && amplitude(s) >= max(minAmplitude * 0.8, 0.35 * medianAmp)
        }

        if travel {
            // Travel signals are double-integrated and high-passed, and the high-pass leaks the
            // movement into its drift estimate where its window runs off the buffer: the still
            // pre-roll and tail come out as ramps of 15–30 cm. The first rep's turnaround then lands
            // ~0.1 s before the hand really stops (fast reps), or its start ~0.5 s after the hand set
            // off (slow reps), and its range – a zero-velocity update between the two – comes out
            // tens of cm short. The last rep may never seem to come back, or, with the far end taken
            // as rest, seem to come back when it never did. Interior reps are fine.
            // So the first and last reps are re-measured on the hand's path integrated between two
            // points where it is still: the pre-roll and the rest after the first rep; the rest
            // before the last rep and the end of the buffer – still after the set; mid-set the hand
            // may be moving there, so a last rep is only added once the series agrees it came back.
            let outward: Double = restHigh ? -1 : 1
            let bufferStart = valid.firstIndex(of: true) ?? 0
            /// Outward position (cm) on the path bridged between still points a and b (clamped to a...b).
            func bridged(_ a: Int, _ b: Int) -> ((Int) -> Double)? {
                guard b > a + 2, let p = signals.travelPath(kind, from: a, to: b) else { return nil }
                return { outward * p[min(max($0, a), b) - a] }
            }
            // The series' turnaround and start are moved to where the path really turns, but only where
            // the path has the hand still clearly moving there (> 10 % of its top speed) – elsewhere
            // noise in the path would decide – and only a fraction of a period (the series is bent,
            // not wrong), so a stretch of stillness never becomes a rep.
            func climb(_ i0: Int, _ lo: Int, _ hi: Int, _ f: (Int) -> Double) -> Int {
                var i = min(max(i0, lo), hi)
                while true {
                    if i < hi && f(i + 1) > f(i) { i += 1 } else if i > lo && f(i - 1) > f(i) { i -= 1 } else { return i }
                }
            }
            func speed(_ p: (Int) -> Double, at i: Int) -> Double {
                i > 0 && i + 1 < n ? abs(p(i + 1) - p(i - 1)) / 2 : 0
            }
            func topSpeed(_ p: (Int) -> Double, _ a: Int, _ b: Int) -> Double {
                a < b ? (a...b).map { speed(p, at: $0) }.max()! : 0
            }
            func turn(_ p: (Int) -> Double, _ r: Raw, until down: Int) -> Int {
                guard speed(p, at: r.peak) > 0.1 * topSpeed(p, r.start, r.peak) else { return r.peak }
                return climb(r.peak, max(r.up, r.peak - period / 4), min(down, r.peak + period / 4), p)
            }
            /// The last still moment before the hand set off: back from where it was a tenth of the
            /// way out to the first low point (not deep into the pre-roll, which only adds noise).
            func setOff(_ p: (Int) -> Double, _ r: Raw, peak: Int, notBefore lo: Int) -> Int {
                let from = max(lo, r.start - period / 2)
                guard from < r.up, speed(p, at: r.start) > 0.1 * topSpeed(p, r.start, peak) else { return r.start }
                let base = (from...r.up).map(p).min()!
                var i = peak
                while i > from && p(i) > base + 0.1 * (p(peak) - base) { i -= 1 }
                while i > from && p(i - 1) < p(i) { i -= 1 }
                return i
            }
            let last = raw.count - 1
            // First rep (wiggles in the pre-roll may come before it).
            for k in 0..<min(last, 3) {
                guard let e = ends[k], let down = raw[k].down, let p = bridged(bufferStart, e) else { break }
                let peak = turn(p, raw[k], until: down)
                let seg = makeSegment(setOff(p, raw[k], peak: peak, notBefore: bufferStart), peak, e)
                segments[k] = seg
                if isRep(seg) { break }
            }
            // Last rep: does it really come back?
            let r = raw[last]
            let repBefore = segments[..<last].contains { $0.map(isRep) ?? false }
            if let p = bridged(repBefore ? r.start : bufferStart, n - 1) {
                // (Only the first rep's turnaround needs moving; this one's is judged, not moved.)
                let peak = repBefore ? r.peak : turn(p, r, until: r.down ?? n - 1)
                let start = repBefore ? r.start : setOff(p, r, peak: peak, notBefore: bufferStart)
                let rest = p(start), reach = p(peak) - rest
                func back(below fraction: Double) -> Int? {
                    guard reach > 0 else { return nil }
                    return ((peak + 1)..<n).first { p($0) - rest < fraction * reach }
                }
                if r.down == nil {
                    // The series never brought it back: count it once both the series (bent at the
                    // end) and the path (noisy over seconds) have had it at least halfway back.
                    let seriesBack = ((r.peak + 1)..<n).contains { valid[$0] && z[$0] < up }
                    if seriesBack, let b = back(below: up) {
                        var e = b
                        for j in b...min(n - 1, b + max(2, period / 2)) where p(j) < p(e) { e = j }
                        segments[last] = makeSegment(start, peak, e)
                    }
                } else if back(below: up) == nil {
                    // Only the bent tail of the series brought it back.
                    segments[last] = nil
                } else if !repBefore, let e = ends[last] {
                    segments[last] = makeSegment(start, peak, e)
                }
            }
        }

        return segments.compactMap { $0 }.filter(isRep)
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
