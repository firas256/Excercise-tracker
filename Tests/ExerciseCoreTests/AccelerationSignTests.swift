import XCTest
@testable import ExerciseCore

/// Calibration measures which way the delivered user acceleration points (CoreMotion reports it
/// as the negative of the physical acceleration) from the hand rising while the arm is lifted.
final class AccelerationSignTests: XCTestCase {

    private struct Pose { var forearm: Vector3; var palm: Vector3 }

    /// Smooth, physically consistent calibration: straight arm pivoting at the shoulder, 0.6 m long.
    private func calibrationSamples(deliveredSign: Double) -> [MotionSample] {
        let wearing = CalibrationProfile.defaultProfile()
        let f = wearing.forearmAxis, p = wearing.palmAxis, r = wearing.radialAxis
        let poses = [
            Pose(forearm: Vector3(0, 0, -1), palm: Vector3(0, 1, 0)),
            Pose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, -1)),
            Pose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, 1)),
            Pose(forearm: Vector3(0, 1, 0), palm: Vector3(0, 0, -1)),
            Pose(forearm: Vector3(0, 0, 1), palm: Vector3(-1, 0, 0)),
        ]
        let rate = 50.0, dt = 1 / rate
        // Timeline of (pose index a, pose index b, fraction)
        var timeline: [(Int, Int, Double)] = []
        for _ in 0..<Int(2.5 * rate) { timeline.append((0, 0, 0)) }
        for i in 1..<poses.count {
            for k in 0..<Int(1.2 * rate) {
                let u = Double(k) / (1.2 * rate)
                timeline.append((i - 1, i, 0.5 - 0.5 * cos(.pi * u)))
            }
            for _ in 0..<Int(2.5 * rate) { timeline.append((i, i, 0)) }
        }
        func frame(_ idx: Int) -> (Vector3, Vector3, Vector3) {
            let (a, b, u) = timeline[max(0, min(timeline.count - 1, idx))]
            let fw = (poses[a].forearm * (1 - u) + poses[b].forearm * u).normalized
            // Rotate the palm about the forearm when turning it over (avoids a zero vector midway).
            let pa0 = poses[a].palm, pb0 = poses[b].palm
            let blend = pa0.dot(pb0) < -0.9
                ? pa0 * cos(.pi * u) + fw.cross(pa0) * sin(.pi * u)
                : pa0 * (1 - u) + pb0 * u
            let pw = blend.orthogonalized(against: fw).normalized
            return (fw, pw, fw.cross(pw))
        }
        var out: [MotionSample] = []
        for i in 0..<timeline.count {
            let (fa, pa, ra) = frame(i - 1), (fb, pb, rb) = frame(i), (fc, pc, rc) = frame(i + 1)
            let omega = (fb.cross((fc - fa) / (2 * dt)) + pb.cross((pc - pa) / (2 * dt)) + rb.cross((rc - ra) / (2 * dt))) * 0.5
            let accel = (fc * 0.6 - fb * 1.2 + fa * 0.6) / (dt * dt) / 9.80665   // hand = 0.6 m · forearm
            func world(_ d: Vector3) -> Vector3 { fb * d.dot(f) + pb * d.dot(p) + rb * d.dot(r) }
            let q = Quaternion(rotationColumns: world(.unitX), world(.unitY), world(.unitZ))
            out.append(MotionSample(
                timestamp: Double(i) * dt,
                gravity: q.conjugate.rotate(Vector3(0, 0, -1)),
                userAcceleration: q.conjugate.rotate(accel) * deliveredSign,
                rotationRate: q.conjugate.rotate(omega),
                attitude: q
            ))
        }
        return out
    }

    private func calibrate(_ samples: [MotionSample]) -> CalibrationProfile? {
        let engine = CalibrationEngine()
        var events = engine.start()
        for s in samples { events += engine.ingest(s) }
        for e in events { if case .finished(let p) = e { return p } }
        return nil
    }

    func testDetectsCoreMotionConvention() throws {
        let profile = try XCTUnwrap(calibrate(calibrationSamples(deliveredSign: -1)))
        XCTAssertEqual(profile.accelerationSign, -1)
    }

    func testDetectsPhysicalConvention() throws {
        let profile = try XCTUnwrap(calibrate(calibrationSamples(deliveredSign: 1)))
        XCTAssertEqual(profile.accelerationSign, 1)
    }

    func testArmSampleUsesPhysicalAcceleration() {
        var profile = CalibrationProfile.defaultProfile()
        let s = MotionSample(timestamp: 0, gravity: Vector3(1, 0, 0), userAcceleration: Vector3(0.5, 0, 0), rotationRate: .zero)
        XCTAssertEqual(profile.armSample(from: s).acceleration.x, -0.5, accuracy: 1e-9)  // default: CoreMotion convention
        profile.accelerationSign = 1
        XCTAssertEqual(profile.armSample(from: s).acceleration.x, 0.5, accuracy: 1e-9)
    }
}
