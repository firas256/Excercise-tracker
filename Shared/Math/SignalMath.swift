import Foundation

/// Small collection of signal-processing helpers used by calibration, rep detection and feature extraction.
enum SignalMath {

    static func mean(_ x: [Double]) -> Double {
        x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count)
    }

    static func standardDeviation(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        let v = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return v.squareRoot()
    }

    /// Linear-interpolated percentile, `p` in 0...100.
    static func percentile(_ x: [Double], _ p: Double) -> Double {
        guard !x.isEmpty else { return 0 }
        let s = x.sorted()
        if s.count == 1 { return s[0] }
        let rank = max(0, min(1, p / 100)) * Double(s.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = min(s.count - 1, lo + 1)
        let f = rank - Double(lo)
        return s[lo] * (1 - f) + s[hi] * f
    }

    static func median(_ x: [Double]) -> Double { percentile(x, 50) }

    /// Centered moving average. Window is clamped to an odd number >= 1.
    static func movingAverage(_ x: [Double], window: Int) -> [Double] {
        guard x.count > 2, window > 1 else { return x }
        let half = window / 2
        var prefix = [Double](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + x[i] }
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count - 1, i + half)
            out[i] = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
        return out
    }

    /// Centered rolling maximum and minimum with the given half-width (in samples).
    static func rollingExtrema(_ x: [Double], halfWidth: Int) -> (max: [Double], min: [Double]) {
        let n = x.count
        guard n > 0 else { return ([], []) }
        let h = max(1, halfWidth)
        var mx = [Double](repeating: 0, count: n)
        var mn = [Double](repeating: 0, count: n)
        // Monotonic deques give O(n) behaviour even for long sets.
        var maxDeque: [Int] = []
        var minDeque: [Int] = []
        var maxHead = 0
        var minHead = 0
        var next = 0
        for i in 0..<n {
            let hi = min(n - 1, i + h)
            while next <= hi {
                while maxDeque.count > maxHead, x[maxDeque[maxDeque.count - 1]] <= x[next] { maxDeque.removeLast() }
                maxDeque.append(next)
                while minDeque.count > minHead, x[minDeque[minDeque.count - 1]] >= x[next] { minDeque.removeLast() }
                minDeque.append(next)
                next += 1
            }
            let lo = i - h
            while maxHead < maxDeque.count, maxDeque[maxHead] < lo { maxHead += 1 }
            while minHead < minDeque.count, minDeque[minHead] < lo { minHead += 1 }
            mx[i] = x[maxDeque[maxHead]]
            mn[i] = x[minDeque[minHead]]
        }
        return (mx, mn)
    }

    /// Unbiased, normalized autocorrelation for lags `minLag...maxLag`.
    /// Returns an array indexed by lag (entries below `minLag` are zero).
    static func autocorrelation(_ x: [Double], minLag: Int, maxLag: Int) -> [Double] {
        let n = x.count
        guard n > 4, maxLag > minLag else { return [] }
        let m = mean(x)
        let d = x.map { $0 - m }
        let variance = d.reduce(0) { $0 + $1 * $1 } / Double(n)
        guard variance > 1e-12 else { return [Double](repeating: 0, count: maxLag + 1) }
        let upper = min(maxLag, n - 2)
        var r = [Double](repeating: 0, count: maxLag + 1)
        guard upper >= minLag else { return r }
        for lag in minLag...upper {
            var s = 0.0
            let count = n - lag
            for i in 0..<count { s += d[i] * d[i + lag] }
            r[lag] = (s / Double(count)) / variance
        }
        return r
    }

    /// Finds the dominant period of a (roughly) periodic signal.
    /// Picks the first autocorrelation peak that is close to the global best, which avoids
    /// locking onto harmonics (2x, 3x the true period).
    static func dominantPeriod(_ x: [Double], minLag: Int, maxLag: Int) -> (lag: Int, score: Double)? {
        let r = autocorrelation(x, minLag: minLag, maxLag: maxLag)
        guard r.count > minLag + 2 else { return nil }
        let usableMax = min(r.count - 2, x.count - max(minLag, x.count / 4))
        guard usableMax > minLag else { return nil }
        var peaks: [(Int, Double)] = []
        for lag in (minLag + 1)...usableMax where r[lag] > r[lag - 1] && r[lag] >= r[lag + 1] && r[lag] > 0.1 {
            peaks.append((lag, r[lag]))
        }
        guard let best = peaks.max(by: { $0.1 < $1.1 }) else { return nil }
        let chosen = peaks.first(where: { $0.1 >= 0.85 * best.1 }) ?? best
        return (chosen.0, chosen.1)
    }

    /// First-order leaky integrator: y[n] = a*y[n-1] + x[n]*dt with a = exp(-dt/tau).
    /// Acts as an integrator plus a high-pass filter that prevents unbounded drift.
    static func leakyIntegrate(_ x: [Double], dt: Double, tau: Double) -> [Double] {
        guard !x.isEmpty else { return [] }
        let a = exp(-dt / tau)
        var y = [Double](repeating: 0, count: x.count)
        var acc = 0.0
        for i in 0..<x.count {
            acc = a * acc + x[i] * dt
            y[i] = acc
        }
        return y
    }

    /// Integrates `x` (after removing its mean) and removes slow drift by subtracting a centered
    /// moving average. Unlike a leaky integrator this introduces no phase shift, so turnaround
    /// points stay where they really are (important for timing and zero-velocity updates).
    static func zeroPhaseIntegrate(_ x: [Double], dt: Double, window: Int) -> [Double] {
        guard !x.isEmpty else { return [] }
        let m = mean(x)
        var y = [Double](repeating: 0, count: x.count)
        var acc = 0.0
        for i in 0..<x.count {
            acc += (x[i] - m) * dt
            y[i] = acc
        }
        let trend = movingAverage(y, window: window)
        for i in 0..<y.count { y[i] -= trend[i] }
        return y
    }

    /// Integrates `x` between two indices (inclusive start, exclusive end) with the trapezoid rule.
    static func integrate(_ x: [Double], from start: Int, to end: Int, dt: Double) -> Double {
        guard end - start > 1, start >= 0, end <= x.count else { return 0 }
        var s = 0.0
        for i in start..<(end - 1) { s += 0.5 * (x[i] + x[i + 1]) * dt }
        return s
    }

    /// Displacement between `start` and `end` from an acceleration trace, assuming the velocity is
    /// zero at both ends (true at the turnaround points of a rep). Linear velocity-drift removal
    /// ("zero-velocity update") keeps double integration accurate over the few seconds of a rep.
    static func zeroVelocityDisplacement(_ accel: [Double], from start: Int, to end: Int, dt: Double) -> Double {
        guard end - start > 2, start >= 0, end <= accel.count else { return 0 }
        let n = end - start
        var v = [Double](repeating: 0, count: n)
        for i in 1..<n {
            v[i] = v[i - 1] + 0.5 * (accel[start + i - 1] + accel[start + i]) * dt
        }
        let drift = v[n - 1]
        var p = 0.0
        for i in 1..<n {
            let c0 = v[i - 1] - drift * Double(i - 1) / Double(n - 1)
            let c1 = v[i] - drift * Double(i) / Double(n - 1)
            p += 0.5 * (c0 + c1) * dt
        }
        return p
    }

    /// Principal axis (largest-variance direction) of a cloud of 3D vectors, via power iteration
    /// on the 3x3 second-moment matrix. Sign is arbitrary.
    static func principalAxis(_ v: [Vector3]) -> Vector3? {
        guard v.count > 3 else { return nil }
        var c = [[Double]](repeating: [0, 0, 0], count: 3)
        for p in v {
            let a = [p.x, p.y, p.z]
            for i in 0..<3 { for j in 0..<3 { c[i][j] += a[i] * a[j] } }
        }
        var b = Vector3(0.577, 0.577, 0.577)
        for _ in 0..<40 {
            let nb = Vector3(
                c[0][0] * b.x + c[0][1] * b.y + c[0][2] * b.z,
                c[1][0] * b.x + c[1][1] * b.y + c[1][2] * b.z,
                c[2][0] * b.x + c[2][1] * b.y + c[2][2] * b.z
            )
            let l = nb.length
            if l < 1e-12 { return nil }
            b = nb / l
        }
        return b
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
}
