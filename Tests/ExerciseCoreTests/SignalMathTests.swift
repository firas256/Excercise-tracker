import XCTest
@testable import ExerciseCore

final class SignalMathTests: XCTestCase {

    func testPercentileAndMedian() {
        let x: [Double] = [5, 1, 3, 2, 4]
        XCTAssertEqual(SignalMath.median(x), 3, accuracy: 1e-9)
        XCTAssertEqual(SignalMath.percentile(x, 0), 1, accuracy: 1e-9)
        XCTAssertEqual(SignalMath.percentile(x, 100), 5, accuracy: 1e-9)
        XCTAssertEqual(SignalMath.percentile(x, 25), 2, accuracy: 1e-9)
    }

    func testRollingExtremaMatchesNaive() {
        var rng = SeededRandom(seed: 7)
        let x = (0..<300).map { _ in rng.gaussian() }
        let h = 17
        let fast = SignalMath.rollingExtrema(x, halfWidth: h)
        for i in 0..<x.count {
            let lo = max(0, i - h), hi = min(x.count - 1, i + h)
            let window = x[lo...hi]
            XCTAssertEqual(fast.max[i], window.max()!, accuracy: 1e-12)
            XCTAssertEqual(fast.min[i], window.min()!, accuracy: 1e-12)
        }
    }

    func testDominantPeriodOfSine() {
        let rate = 50.0
        let period = 2.6
        let x = (0..<Int(15 * rate)).map { sin(2 * .pi * Double($0) / rate / period) }
        let p = SignalMath.dominantPeriod(x, minLag: 30, maxLag: 400)
        XCTAssertNotNil(p)
        XCTAssertEqual(Double(p!.lag) / rate, period, accuracy: 0.05)
        XCTAssertGreaterThan(p!.score, 0.9)
    }

    func testZeroVelocityDisplacement() {
        // Smooth 0 → 0.4 m move over 1.5 s: x(t) = 0.2(1 - cos(πt/T)); a = 0.2(π/T)² cos(πt/T)
        let rate = 50.0, T = 1.5
        let n = Int(T * rate) + 1
        var rng = SeededRandom(seed: 3)
        let a = (0..<n).map { i -> Double in
            let t = Double(i) / rate
            return 0.2 * pow(.pi / T, 2) * cos(.pi * t / T) + 0.05 * rng.gaussian() + 0.08 // bias
        }
        let d = SignalMath.zeroVelocityDisplacement(a, from: 0, to: n, dt: 1 / rate)
        XCTAssertEqual(d, 0.4, accuracy: 0.03)
    }

    func testPrincipalAxis() {
        let axis = Vector3(1, 2, -0.5).normalized
        var rng = SeededRandom(seed: 9)
        let pts = (0..<200).map { i in axis * sin(Double(i) * 0.1) * 3 + Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.05 }
        let found = SignalMath.principalAxis(pts)!
        XCTAssertGreaterThan(abs(found.dot(axis)), 0.99)
    }

    func testQuaternionRotation() {
        let q = Quaternion(axis: .unitZ, angle: .pi / 2)
        let v = q.rotate(.unitX)
        XCTAssertEqual(v.x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.y, 1, accuracy: 1e-9)
        let back = q.conjugate.rotate(v)
        XCTAssertEqual(back.x, 1, accuracy: 1e-9)
    }
}
