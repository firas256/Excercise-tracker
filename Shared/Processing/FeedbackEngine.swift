import Foundation

/// Turns detected reps into per-rep metrics and coaching feedback (range, tempo, control, fatigue).
enum FeedbackEngine {

    struct Thresholds {
        /// A rep shorter than this fraction of the set's reference range is "partial".
        var partialFraction = 0.8
        /// Lifting faster than this (s) is flagged as rushed.
        var minConcentric = 0.45
        /// Lowering faster than this (s) is flagged.
        var minEccentric = 0.7
        /// Peak angular speed (deg/s) above which curls/raises are considered swung.
        var momentumAngularSpeed = 450.0
        /// Speed loss vs. the best early rep that marks a rep as slowing down.
        var slowingDownLoss = 0.3
    }

    /// A rep covering less than this fraction of the required range isn't counted.
    static let minimumCountedFraction = 0.5

    /// The user's full range of motion for an exercise, in the unit of the signal the reps were
    /// counted on, from their calibration: their hanging arm, their arm at shoulder height (forward
    /// / to the side), their overhead reach, and their arm length and height. nil = no expectation.
    static func fullRange(for exercise: ExerciseType, signal: RepSignalKind, body: BodyProfile) -> Double? {
        switch signal {
        case .elevation, .rotation:
            switch exercise {
            case .bicepCurl, .hammerCurl: return body.forwardElevation + 40 + 85   // hanging → well above horizontal
            case .tricepsPushdown: return body.forwardElevation + 10 + 85          // about horizontal → straight down
            case .lateralRaise: return body.sideElevation - 5 + 85                 // hanging → shoulder height
            case .frontRaise: return body.forwardElevation - 5 + 85
            case .overheadTricepsExtension: return body.overheadElevation - 5 + 40 // behind the head → straight up
            case .skullCrusher: return 90
            case .tricepsKickback: return 80
            default: return nil
            }
        case .vertical:
            switch exercise {
            case .shoulderPress: return body.fullPressTravel * 100
            case .squat, .gobletSquat: return body.parallelSquatTravel * 100
            default: return nil
            }
        case .forearm:
            return nil
        }
    }

    /// Separates reps that are too short to count: less than half the required range, which is the
    /// larger of the user's full range for the exercise (when the exercise is known for sure) and
    /// their best reps in this set. Counted reps are renumbered 1…n.
    static func separateTooShort(_ reps: [RepMetrics], exercise: ExerciseType?, exerciseIsCertain: Bool,
                                 signal: RepSignalKind, body: BodyProfile)
        -> (counted: [RepMetrics], tooShort: [RepMetrics], required: Double) {
        guard !reps.isEmpty else { return ([], [], 0) }
        let ranges = reps.map { $0.rangeOfMotion }
        var required = ranges.count >= 3 ? SignalMath.percentile(ranges, 85) : (ranges.max() ?? 0)
        if exerciseIsCertain, let exercise, let full = fullRange(for: exercise, signal: signal, body: body), full > 0 {
            required = max(required, full)
        }
        var counted: [RepMetrics] = []
        var tooShort: [RepMetrics] = []
        for rep in reps {
            if rep.rangeOfMotion < minimumCountedFraction * required {
                tooShort.append(rep)
            } else {
                var r = rep
                r.index = counted.count + 1
                counted.append(r)
            }
        }
        return (counted, tooShort, required)
    }

    /// Attempts the rep finder skipped (it ignores movements under about half of the neighbouring
    /// reps): after a rep is back at rest, the forearm went part of the way – at least a quarter but
    /// under half the required range – and came back. Judged on the forearm angle (from gravity, so it
    /// doesn't drift), whichever signal counted the reps, for exercises whose reps clearly move it.
    /// Excursions that pause at the top for long (raising the wrist to read the watch) are ignored;
    /// so is the time before the first rep (picking up the weight).
    static func skippedAttempts(_ signals: MotionSignals, detection: RepDetectionResult, counted: [RepMetrics],
                                exercise: ExerciseType?, exerciseIsCertain: Bool, body: BodyProfile) -> [RepMetrics] {
        let segs = detection.segments
        guard counted.count >= 2, !segs.isEmpty, signals.count == detection.series.count else { return [] }
        let swings = counted.map { $0.peakElevation - $0.startElevation }
        let typical = SignalMath.median(swings)
        guard abs(typical) >= 30 else { return [] }  // these reps barely change the forearm angle
        let direction: Double = typical > 0 ? 1 : -1
        var required = SignalMath.percentile(swings.map { abs($0) }, 85)
        if exerciseIsCertain, let exercise, let full = fullRange(for: exercise, signal: .elevation, body: body) {
            required = max(required, full)
        }
        let minimum = max(RepDetector.minimumAmplitude(.elevation), 0.25 * required)
        let maximum = minimumCountedFraction * required
        let x = detection.signal == .elevation
            ? detection.series
            : SignalMath.movingAverage(signals.elevation, window: max(3, Int(0.14 / signals.dt) | 1))
        let t0 = signals.samples.first?.t ?? 0
        var attempts: [RepMetrics] = []
        for (k, seg) in segs.enumerated() {
            let stop = k + 1 < segs.count ? segs[k + 1].start : x.count - 1
            // Where this rep is back at rest: past the turnaround, down near its starting level, then
            // to the bottom of that return.
            let base = x[seg.start]
            let amplitude = abs(x[seg.peak] - base)
            var i = seg.peak
            while i < stop && (x[i] - base) * direction > 0.3 * amplitude { i += 1 }
            while i < stop && (x[i + 1] - x[i]) * direction <= 0.5 { i += 1 }
            guard stop > i + 2 else { continue }
            let rest = x[i]
            func height(_ j: Int) -> Double { (x[j] - rest) * direction }
            var peak = i
            for j in i...stop where height(j) > height(peak) { peak = j }
            let excursion = height(peak)
            guard excursion >= minimum, excursion < maximum else { continue }
            // Came back towards rest (a full rep still on its way up isn't an attempt)…
            guard (peak...stop).contains(where: { height($0) <= 0.3 * excursion }) else { continue }
            // …and didn't linger at the top (that's a look at the watch, not a rep).
            let nearTop = (i...stop).filter { height($0) >= 0.85 * excursion }.count
            guard Double(nearTop) * signals.dt <= 1.5 else { continue }
            attempts.append(RepMetrics(
                index: 0, startTime: signals.samples[i].t - t0, duration: Double(stop - i) * signals.dt,
                concentricDuration: 0, eccentricDuration: 0, rangeOfMotion: excursion, unit: .degrees,
                rangeFraction: excursion / required, meanConcentricSpeed: 0, peakSpeed: 0,
                startElevation: x[i], peakElevation: x[peak], issues: [], score: 0
            ))
        }
        return attempts
    }

    static func repMetrics(_ signals: MotionSignals, detection: RepDetectionResult,
                           exercise: ExerciseType?, thresholds: Thresholds = Thresholds(),
                           body: BodyProfile = .typical) -> [RepMetrics] {
        let dt = signals.dt
        let kind = detection.signal
        let segs = detection.segments
        guard !segs.isEmpty else { return [] }
        let t0 = signals.samples.first?.t ?? 0
        let eccentricFirst = exercise?.eccentricFirst ?? false
        let ballistic = exercise == .kettlebellSwing

        var ranges: [Double] = []
        var speeds: [Double] = []
        var partial: [RepMetrics] = []
        let x = detection.series
        for (i, seg) in segs.enumerated() {
            let range = signals.range(kind, from: seg.start, to: seg.peak)
            let away = max(dt, Double(seg.awayEnd - seg.moveStart) * dt)
            let back = max(dt, Double(seg.moveEnd - seg.returnStart) * dt)
            let concentric = eccentricFirst ? back : away
            let eccentric = eccentricFirst ? away : back
            let rawSpan = abs(x[seg.peak] - x[seg.start])
            let scale = rawSpan > 1e-6 ? range / rawSpan : 1
            var peakSpeed = 0.0
            if seg.end > seg.start + 1 {
                for j in (seg.start + 1)...seg.end {
                    peakSpeed = max(peakSpeed, abs(x[j] - x[j - 1]) / dt * scale)
                }
            }
            let meanSpeed = range / concentric
            ranges.append(range)
            speeds.append(meanSpeed)
            partial.append(RepMetrics(
                index: i + 1,
                startTime: signals.samples[seg.moveStart].t - t0,
                duration: Double(seg.moveEnd - seg.moveStart) * dt,
                concentricDuration: concentric,
                eccentricDuration: eccentric,
                rangeOfMotion: range,
                unit: kind.unit,
                rangeFraction: 1,
                meanConcentricSpeed: meanSpeed,
                peakSpeed: peakSpeed,
                startElevation: signals.elevation[seg.start],
                peakElevation: signals.elevation[seg.peak],
                issues: [],
                score: 100
            ))
        }

        // Reference range: a high percentile so a few partial reps don't lower the bar.
        let reference = max(ranges.count >= 3 ? SignalMath.percentile(ranges, 85) : (ranges.max() ?? 1), 1e-6)
        let earlyBestSpeed = speeds.prefix(3).max() ?? 0

        return partial.enumerated().map { (i, rep) in
            var r = rep
            r.rangeFraction = min(1.2, rep.rangeOfMotion / reference)
            var issues: [RepIssue] = []
            if r.rangeFraction < thresholds.partialFraction { issues.append(.partialRange) }
            issues.append(contentsOf: positionIssues(rep, exercise: exercise, body: body))
            if !ballistic {
                if rep.concentricDuration < thresholds.minConcentric { issues.append(.rushedLift) }
                if rep.eccentricDuration < thresholds.minEccentric
                    || (rep.eccentricDuration < 0.6 * rep.concentricDuration && rep.eccentricDuration < 1.2) {
                    issues.append(.rushedLowering)
                }
                if let e = exercise, [.bicepCurl, .hammerCurl, .lateralRaise, .frontRaise].contains(e),
                   rep.unit == .degrees, rep.peakSpeed > thresholds.momentumAngularSpeed {
                    issues.append(.momentum)
                }
            }
            if i >= 3, earlyBestSpeed > 0, rep.meanConcentricSpeed < (1 - thresholds.slowingDownLoss) * earlyBestSpeed {
                issues.append(.slowingDown)
            }
            r.issues = issues
            r.score = score(for: r)
            return r
        }
    }

    /// Exercise-specific checks on the absolute forearm angle (thanks to calibration).
    /// Top/bottom checks against the user's own reference angles from calibration: their straight
    /// arm at shoulder height (forward / to the side) and their overhead reach. The lowest and
    /// highest point of the rep are used, whichever end the rep started from. (A hanging arm is
    /// -90° by definition, because calibration takes "arms down" as the forearm's direction.)
    static func positionIssues(_ rep: RepMetrics, exercise: ExerciseType?, body: BodyProfile = .typical) -> [RepIssue] {
        guard let exercise else { return [] }
        let low = min(rep.startElevation, rep.peakElevation)
        let high = max(rep.startElevation, rep.peakElevation)
        var issues: [RepIssue] = []
        switch exercise {
        case .bicepCurl, .hammerCurl:
            if low > -60 { issues.append(.incompleteBottom) }
            if high < body.forwardElevation + 15 { issues.append(.incompleteTop) }
        case .lateralRaise:
            if high < body.sideElevation - 25 { issues.append(.incompleteTop) }
        case .frontRaise:
            if high < body.forwardElevation - 25 { issues.append(.incompleteTop) }
        case .tricepsPushdown:
            if low > -55 { issues.append(.incompleteBottom) }
        case .overheadTricepsExtension:
            if high < body.overheadElevation - 25 { issues.append(.incompleteTop) }
        case .skullCrusher:
            if high < 55 { issues.append(.incompleteTop) }
        default:
            break
        }
        return issues
    }

    static func score(for rep: RepMetrics) -> Int {
        var s = 100.0
        for issue in rep.issues {
            switch issue {
            case .partialRange: s -= min(40, (1 - rep.rangeFraction) * 100)
            case .incompleteTop, .incompleteBottom: s -= 15
            case .rushedLift: s -= 10
            case .rushedLowering: s -= 15
            case .momentum: s -= 15
            case .slowingDown: s -= 0
            }
        }
        return Int(max(0, min(100, s)).rounded())
    }

    static func setFeedback(_ reps: [RepMetrics], exercise: ExerciseType?, body: BodyProfile = .typical,
                            notCounted: Int = 0, requiredRange: Double? = nil) -> SetFeedback {
        guard !reps.isEmpty else { return .empty }
        let ranges = reps.map { $0.rangeOfMotion }
        let avgRange = SignalMath.mean(ranges)
        let variation = avgRange > 0 ? SignalMath.standardDeviation(ranges) / avgRange : 0
        let avgCon = SignalMath.mean(reps.map { $0.concentricDuration })
        let avgEcc = SignalMath.mean(reps.map { $0.eccentricDuration })
        let speeds = reps.map { $0.meanConcentricSpeed }
        let best = speeds.prefix(3).max() ?? 0
        let lastSpeed = SignalMath.mean(Array(speeds.suffix(2)))
        let velocityLoss = (reps.count >= 4 && best > 0) ? max(0, 1 - lastSpeed / best) : 0
        let score = reps.reduce(0) { $0 + $1.score } / reps.count
        let n = reps.count

        func count(_ issue: RepIssue) -> Int { reps.filter { $0.issues.contains(issue) }.count }
        func frequent(_ issue: RepIssue) -> Bool { count(issue) >= max(1, Int((0.25 * Double(n)).rounded(.up))) }

        var tips: [FeedbackTip] = []
        if notCounted > 0 {
            let half = (requiredRange ?? 0) * minimumCountedFraction
            let limit = half > 0 ? String(format: " (under %.0f%@)", half, reps[0].unit.symbol) : ""
            tips.append(FeedbackTip(kind: .warning, title: notCounted == 1 ? "1 rep not counted" : "\(notCounted) reps not counted",
                                    detail: "They covered less than half of the full range\(limit). Move through the whole range for the rep to count."))
        }
        if frequent(.partialRange) {
            tips.append(FeedbackTip(kind: .warning, title: "Use your full range",
                                    detail: "\(count(.partialRange)) of \(n) reps were shorter than your best reps. A slightly lighter weight can help you reach full range."))
        }
        if frequent(.incompleteBottom) {
            let detail = exercise == .tricepsPushdown
                ? "Lock your elbows out at the bottom of each rep."
                : "Let your arm extend fully at the bottom before the next rep."
            tips.append(FeedbackTip(kind: .warning, title: "Finish the bottom", detail: detail))
        }
        if frequent(.incompleteTop) {
            let detail: String
            switch exercise {
            case .lateralRaise?, .frontRaise?: detail = "Raise your arms to shoulder height on every rep."
            case .overheadTricepsExtension?, .skullCrusher?: detail = "Fully straighten your elbows at the top."
            default: detail = "Squeeze all the way to the top of the movement."
            }
            tips.append(FeedbackTip(kind: .warning, title: "Finish the top", detail: detail))
        }
        // Reach / depth for the user's size (arm length and height from calibration).
        if n >= 3, reps[0].unit == .centimeters {
            let forWhom = body.isArmLengthMeasured ? "for your arm length" : "for an average-sized adult"
            switch exercise {
            case .shoulderPress?:
                let full = body.fullPressTravel * 100
                if avgRange < 0.55 * full {
                    tips.append(FeedbackTip(kind: .warning, title: "Press all the way up",
                                            detail: String(format: "Your reps moved about %.0f cm – a full press %@ is about %.0f cm. Straighten your arms overhead each rep.", avgRange, forWhom, full)))
                }
            case .squat?, .gobletSquat?:
                let full = body.parallelSquatTravel * 100
                if avgRange < 0.5 * full {
                    let height = body.isArmLengthMeasured ? String(format: " (about %.2f m tall)", body.estimatedHeight) : ""
                    tips.append(FeedbackTip(kind: .warning, title: "Squat deeper",
                                            detail: String(format: "Your hands dropped about %.0f cm – reaching parallel %@%@ is about %.0f cm.", avgRange, forWhom, height, full)))
                }
            default:
                break
            }
        }
        if frequent(.rushedLowering) {
            tips.append(FeedbackTip(kind: .warning, title: "Slow the lowering",
                                    detail: String(format: "You lowered in %.1f s on average – aim for 2–3 s to build more strength and protect your joints.", avgEcc)))
        }
        if frequent(.rushedLift) {
            tips.append(FeedbackTip(kind: .warning, title: "Lift with control",
                                    detail: String(format: "Lifting took only %.1f s – aim for about 1–2 s without bouncing.", avgCon)))
        }
        if frequent(.momentum) {
            tips.append(FeedbackTip(kind: .warning, title: "Less swinging",
                                    detail: "Keep your upper arms and torso still so the target muscle does the work."))
        }
        if velocityLoss >= 0.3 {
            tips.append(FeedbackTip(kind: .info, title: "Close to failure",
                                    detail: String(format: "Your lifting speed dropped %.0f%% from the first reps – a hard set. Rest 2–3 min before the next one.", velocityLoss * 100)))
        } else if n >= 6 && velocityLoss < 0.1 && score >= 80 {
            tips.append(FeedbackTip(kind: .info, title: "Room to progress",
                                    detail: "Rep speed barely dropped. If this felt easy, try a little more weight next set."))
        }
        if variation < 0.08 && n >= 3 {
            tips.append(FeedbackTip(kind: .positive, title: "Very consistent",
                                    detail: String(format: "Range of motion varied only %.0f%% between reps.", variation * 100)))
        } else if variation > 0.2 {
            tips.append(FeedbackTip(kind: .warning, title: "Inconsistent range",
                                    detail: String(format: "Range varied %.0f%% between reps – try to make every rep look the same.", variation * 100)))
        }
        if !tips.contains(where: { $0.kind == .warning }) {
            tips.insert(FeedbackTip(kind: .positive, title: "Clean set", detail: "Controlled reps through a full range. Nice work!"), at: 0)
        }
        tips.append(FeedbackTip(kind: .info, title: "Tempo",
                                detail: String(format: "%.1f s up · %.1f s down on average.", avgCon, avgEcc)))

        return SetFeedback(score: score, averageRange: avgRange, unit: reps[0].unit, rangeVariation: variation,
                           averageConcentric: avgCon, averageEccentric: avgEcc, velocityLoss: velocityLoss, tips: tips)
    }

    /// Shown (and announced with its own tap) when a rep was too short to count.
    static let notCountedCue = "Too short – not counted"

    /// One short line for the watch after each rep.
    static func liveCue(for rep: RepMetrics) -> String {
        if let issue = rep.issues.first(where: { $0 != .slowingDown }) { return issue.shortText }
        if rep.issues.contains(.slowingDown) { return "Slowing down – last reps?" }
        return "Good rep"
    }
}
