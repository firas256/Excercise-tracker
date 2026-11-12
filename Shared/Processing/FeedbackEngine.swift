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

    static func repMetrics(_ signals: MotionSignals, detection: RepDetectionResult,
                           exercise: ExerciseType?, thresholds: Thresholds = Thresholds()) -> [RepMetrics] {
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
            issues.append(contentsOf: positionIssues(rep, exercise: exercise))
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
    static func positionIssues(_ rep: RepMetrics, exercise: ExerciseType?) -> [RepIssue] {
        guard let exercise else { return [] }
        var issues: [RepIssue] = []
        switch exercise {
        case .bicepCurl, .hammerCurl:
            if rep.startElevation > -60 { issues.append(.incompleteBottom) }
            if rep.peakElevation < 15 { issues.append(.incompleteTop) }
        case .lateralRaise, .frontRaise:
            if rep.peakElevation < -25 { issues.append(.incompleteTop) }
        case .tricepsPushdown:
            if rep.peakElevation > -55 { issues.append(.incompleteBottom) }
        case .overheadTricepsExtension, .skullCrusher:
            if rep.startElevation < 55 { issues.append(.incompleteTop) }
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

    static func setFeedback(_ reps: [RepMetrics], exercise: ExerciseType?) -> SetFeedback {
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

    /// One short line for the watch after each rep.
    static func liveCue(for rep: RepMetrics) -> String {
        if let issue = rep.issues.first(where: { $0 != .slowingDown }) { return issue.shortText }
        if rep.issues.contains(.slowingDown) { return "Slowing down – last reps?" }
        return "Good rep"
    }
}
