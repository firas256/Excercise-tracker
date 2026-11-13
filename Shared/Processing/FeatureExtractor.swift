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

        // Which half of the rep is quicker, rising or lowering (the effortful half usually is).
        // And the radius the watch swings on: vertical travel per change in sin(forearm angle).
        var biases: [Double] = []
        var radii: [Double] = []
        for (seg, v) in zip(segs, vDisp) {
            let e0 = signals.elevation[seg.start], e1 = signals.elevation[seg.peak]
            let awayIsUp: Bool
            if abs(e1 - e0) >= 20 { awayIsUp = e1 > e0 } else if abs(v) >= 8 { awayIsUp = v > 0 } else { awayIsUp = true }
            if abs(e1 - e0) >= 20 || abs(v) >= 8 {
                let away = Double(max(1, seg.awayEnd - seg.moveStart)), back = Double(max(1, seg.moveEnd - seg.returnStart))
                let up = awayIsUp ? away : back, down = awayIsUp ? back : away
                biases.append((down - up) / (down + up))
            }
            let sinChange = sin(e1 * .pi / 180) - sin(e0 * .pi / 180)
            if abs(sinChange) >= 0.35 { radii.append(abs(v) / abs(sinChange)) }
        }
        let upTempoBias = biases.count >= 2 ? SignalMath.median(biases) : nil
        let pivotRadius = radii.count >= 2 ? SignalMath.median(radii) : nil

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
            repPeriod: repPeriod,
            upTempoBias: upTempoBias,
            pivotRadius: pivotRadius
        )
    }

    /// Heuristic filter so walking between machines is not logged as a set.
    static func looksLikeWalking(_ f: MotionFeatures) -> Bool {
        f.repPeriod < 1.3 && f.startElevation < -60 && f.peakElevation < -45
            && f.rotationAmplitude < 50 && f.verticalAmplitude < 15
    }
}
