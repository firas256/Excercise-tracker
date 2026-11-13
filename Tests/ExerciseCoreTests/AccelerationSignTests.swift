import XCTest
@testable import ExerciseCore

/// Calibration measures which way the delivered user acceleration points (CoreMotion reports it
/// as the negative of the physical acceleration) from the hand rising while the arm is lifted.
final class AccelerationSignTests: XCTestCase {

    private func calibrationSamples(deliveredSign: Double) -> [MotionSample] {
        SyntheticCalibration.samples(armLength: 0.6, deliveredSign: deliveredSign)
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
