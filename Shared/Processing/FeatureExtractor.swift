import Foundation

enum FeatureExtractor {

    /// Builds the classifier feature vector from detected reps. Needs at least one rep.
    static func extract(_ signals: MotionSignals, detection: RepDetectionResult) -> MotionFeatures? {
        let segs = detection.segments
        guard let first = segs.first, let last = segs.last else { return nil }
        let samples = signals.samples

        let startElevation = SignalMath.median(segs.map { signals.elevation[$0.start] })
        let peakElevation = SignalMath.median(segs.map { signals.elevation[$0.peak] })

        // Grip / palm orientation while the forearm is roughly horizontal.
        var cosSum = 0.0, sinSum = 0.0, count = 0
        for i in first.start...last.end where samples[i].horizontality > 0.5 {
            let g = samples[i].gravity
            let r = (g.y * g.y + g.z * g.z).squareRoot()
            guard r > 0.3 else { continue }
            cosSum += g.y / r
            sinSum += g.z / r
            count += 1
        }
        let span = last.end - first.start + 1
        var palmDown: Double?
        var thumbUp: Double?
        if count >= 10, Double(count) >= 0.15 * Double(span) {
            palmDown = cosSum / Double(count)
            thumbUp = abs(sinSum / Double(count))
        }

        let rotationAmps = segs.map { signals.range(.rotation, from: $0.start, to: $0.peak) }
        let rotationAmplitude = SignalMath.median(rotationAmps)
        var axisTwist: Double?, axisPalm: Double?, axisRadial: Double?
        if rotationAmplitude >= 20, let axis = signals.rotationAxis {
            let a = axis.absolute
            axisTwist = a.x
            axisPalm = a.y
            axisRadial = a.z
        }

        let yawAmplitude = SignalMath.median(segs.map { signals.yawRange(from: $0.start, to: $0.peak) })
        let vDisp = segs.map { signals.verticalDisplacement(from: $0.start, to: $0.peak) }
        let fDisp = segs.map { signals.forearmDisplacement(from: $0.start, to: $0.peak) }
        let verticalAmplitude = SignalMath.median(vDisp.map { abs($0) })
        let forearmAmplitude = SignalMath.median(fDisp.map { abs($0) })
        let startsHigh = Double(vDisp.filter { $0 < 0 }.count) / Double(vDisp.count)
        let pushDirection = SignalMath.mean(fDisp.map { SignalMath.clamp($0 / 5, -1, 1) })
        let repPeriod = SignalMath.median(segs.map { Double($0.end - $0.start) * signals.dt })

        return MotionFeatures(
            startElevation: startElevation,
            peakElevation: peakElevation,
            palmDown: palmDown,
            thumbUp: thumbUp,
            axisTwist: axisTwist,
            axisPalm: axisPalm,
            axisRadial: axisRadial,
            rotationAmplitude: rotationAmplitude,
            yawAmplitude: yawAmplitude,
            verticalAmplitude: verticalAmplitude,
            forearmAmplitude: forearmAmplitude,
            startsHigh: startsHigh,
            pushDirection: pushDirection,
            repPeriod: repPeriod
        )
    }

    /// Heuristic filter so walking between machines is not logged as a set.
    static func looksLikeWalking(_ f: MotionFeatures) -> Bool {
        f.repPeriod < 1.3 && f.startElevation < -60 && f.peakElevation < -45
            && f.rotationAmplitude < 50 && f.verticalAmplitude < 15
    }
}
