import XCTest
@testable import ExerciseCore

/// Calibration measures the user's own body: arm length from how far the watch rises while the
/// straight arm swings up, and their personal reference angles.
final class BodyProfileTests: XCTestCase {

    private func calibrate(_ samples: [MotionSample]) -> CalibrationProfile? {
        let engine = CalibrationEngine()
        var events = engine.start()
        for s in samples { events += engine.ingest(s) }
        for e in events { if case .finished(let p) = e { return p } }
        return nil
    }

    func testArmLengthIsMeasuredForShortAndLongArms() throws {
        for length in [0.45, 0.55, 0.68] {
            for sign in [-1.0, 1.0] {
                let samples = SyntheticCalibration.samples(armLength: length, deliveredSign: sign, noiseSeed: 7)
                let profile = try XCTUnwrap(calibrate(samples), "calibration didn't finish")
                let measured = try XCTUnwrap(profile.armLength, "no arm length for \(length) m")
                print("arm \(length) m (sign \(sign)) → measured \(String(format: "%.3f", measured)) m")
                XCTAssertEqual(measured, length, accuracy: 0.05 * length + 0.01)
            }
        }
    }

    func testPersonalAnglesAreRecorded() throws {
        let samples = SyntheticCalibration.samples(armLength: 0.55, overheadElevation: 72)
        let profile = try XCTUnwrap(calibrate(samples))
        let body = profile.body
        XCTAssertEqual(body.overheadElevation, 72, accuracy: 3)
        XCTAssertEqual(body.forwardElevation, 0, accuracy: 3)
        XCTAssertEqual(body.sideElevation, 0, accuracy: 3)
        XCTAssertGreaterThan(body.supinationRange, 160)
    }

    func testDerivedMeasurementsFollowBodyProportions() {
        var body = BodyProfile.typical
        XCTAssertFalse(body.isArmLengthMeasured)
        XCTAssertEqual(body.estimatedHeight, 1.72, accuracy: 0.01)
        body.measuredArmLength = 0.48  // shorter arms
        XCTAssertLessThan(body.estimatedHeight, 1.55)
        XCTAssertLessThan(body.forearmLength, BodyProfile.typical.forearmLength)
        XCTAssertEqual(body.forearmLength + body.upperArmLength, body.armLength, accuracy: 0.005)  // shoulder→elbow→watch
        XCTAssertLessThan(body.sizeScale, 1)
        XCTAssertLessThan(body.fullPressTravel, BodyProfile.typical.fullPressTravel)
    }

    func testOldSavedProfilesStillLoad() throws {
        // A profile saved before arm length existed decodes, with nothing measured.
        let old = CalibrationProfile.defaultProfile()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["armLength", "forwardElevation", "sideElevation"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(CalibrationProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.armLength)
        XCTAssertEqual(decoded.body.armLength, BodyProfile.typicalArmLength)
    }
}
