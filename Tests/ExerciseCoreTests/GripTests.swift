import XCTest
@testable import ExerciseCore

/// Curls and pushdowns move the forearm through similar angles; the grip (how the wrist is turned)
/// and not where a rep happens to "start" must decide between them.
final class GripTests: XCTestCase {

    private func top(_ exercise: ExerciseType, grip: Grip? = nil, restAtEnd: Bool = false, seed: UInt64 = 42,
                     analyzer: SetAnalyzer = SetAnalyzer()) throws -> [ExerciseCandidate] {
        var o = SyntheticMotion.Options()
        o.grip = grip
        o.restAtEnd = restAtEnd
        o.seed = seed
        let samples = try XCTUnwrap(SyntheticMotion.generate(exercise, options: o))
        return analyzer.analyze(samples).candidates
    }

    func testCurlsAndPushdownsByGripWhicheverEndTheSetStarts() throws {
        let cases: [(ExerciseType, Grip?, ExerciseType)] = [
            (.bicepCurl, nil, .bicepCurl),             // palm up, watch face down
            (.hammerCurl, nil, .hammerCurl),           // thumb up
            (.tricepsPushdown, .pronated, .tricepsPushdown),  // straight bar
            (.tricepsPushdown, .neutral, .tricepsPushdown),   // rope: watch face to the side
        ]
        var failures: [String] = []
        for (exercise, grip, expected) in cases {
            for restAtEnd in [false, true] {
                for seed: UInt64 in [1, 2] {
                    let c = try top(exercise, grip: grip, restAtEnd: restAtEnd, seed: seed)
                    if c.first?.exercise != expected {
                        let got = c.prefix(3).map { "\($0.exercise.rawValue) \(Int($0.probability * 100))%" }
                        failures.append("\(exercise.rawValue) grip \(grip?.rawValue ?? "default") restAtEnd \(restAtEnd) seed \(seed) → \(got)")
                    }
                }
            }
        }
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    func testSmallAndTallPeopleWithTheirOwnMeasurements() throws {
        // The synthetic movements are modelled on a 0.6 m arm; scale them and give the analyzer
        // the matching measured arm length.
        for scale in [0.78, 1.0, 1.2] {
            let body = BodyProfile(forwardElevation: 0, sideElevation: 0, overheadElevation: 85, supinationRange: 175,
                                   measuredArmLength: 0.6 * scale)
            let analyzer = SetAnalyzer(body: body)
            for (exercise, grip) in [(ExerciseType.bicepCurl, nil), (.hammerCurl, nil), (.tricepsPushdown, Grip.pronated),
                                     (.tricepsPushdown, .neutral)] as [(ExerciseType, Grip?)] {
                for restAtEnd in [false, true] {
                    var o = SyntheticMotion.Options()
                    o.grip = grip
                    o.restAtEnd = restAtEnd
                    o.bodyScale = scale
                    let samples = try XCTUnwrap(SyntheticMotion.generate(exercise, options: o))
                    let c = analyzer.analyze(samples).candidates
                    XCTAssertEqual(c.first?.exercise, exercise,
                                   "size \(scale) \(exercise) \(grip?.rawValue ?? "") restAtEnd \(restAtEnd) → \(c.prefix(3))")
                }
            }
            // Raises swing from the shoulder: still told apart from curls at every size.
            var o = SyntheticMotion.Options()
            o.bodyScale = scale
            let raise = try XCTUnwrap(SyntheticMotion.generate(.frontRaise, options: o))
            let top3 = analyzer.analyze(raise).candidates.prefix(3).map { $0.exercise }
            XCTAssert(top3.contains(.frontRaise), "size \(scale) front raise → \(top3)")
            XCTAssertFalse(top3.first == .bicepCurl || top3.first == .tricepsPushdown, "size \(scale) front raise → \(top3)")
        }
    }

    func testGripIsReadRelativeToTheUsersOwnPalmUp() throws {
        // Someone whose forearm only turns ~140° still curls "palm up" as far as they can.
        var o = SyntheticMotion.Options()
        o.seed = 3
        let curl = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl, options: o))
        let limited = curl.map { s -> ArmSample in
            var s = s
            // Rotate the measured roll back by 40° (palm up reads 140° instead of 180°). A real
            // forearm stops short on one consistent side (the thumb side), hence the fixed sign.
            let roll = atan2(s.gravity.z, s.gravity.y) * 180 / .pi
            let r = -(abs(roll) - 40) * .pi / 180
            let len = (s.gravity.y * s.gravity.y + s.gravity.z * s.gravity.z).squareRoot()
            s.gravity = Vector3(s.gravity.x, len * cos(r), len * sin(r))
            return s
        }
        var body = BodyProfile.typical
        body.supinationRange = 140
        let features = try XCTUnwrap(SetAnalyzer(body: body).analyze(limited).features)
        XCTAssertEqual(GripModel.grip(of: features, body: body), .supinated)
        let curlFactor = GripModel.factor(for: .bicepCurl, features: features, body: body)
        let pushdownFactor = GripModel.factor(for: .tricepsPushdown, features: features, body: body)
        XCTAssertGreaterThan(curlFactor, 0.8)
        // Underhand pushdowns exist, so palm-up is unusual for a pushdown, not impossible.
        XCTAssertLessThanOrEqual(pushdownFactor, 0.5 + 1e-6)
        XCTAssertGreaterThan(curlFactor / pushdownFactor, 1.8)
    }

    func testGripsTheUserConfirmedCountAsNormal() throws {
        // Someone who does their pushdowns underhand: palm up is unusual for a pushdown – until
        // they've confirmed a few such sets.
        func features(_ seed: UInt64) throws -> MotionFeatures {
            var o = SyntheticMotion.Options()
            o.grip = .supinated
            o.seed = seed
            let samples = try XCTUnwrap(SyntheticMotion.generate(.tricepsPushdown, options: o))
            return try XCTUnwrap(SetAnalyzer().analyze(samples, lockedExercise: .tricepsPushdown).features)
        }
        let set = try features(9)
        let before = GripModel.factor(for: .tricepsPushdown, features: set, body: .typical)
        var personal = ClassifierPersonalization()
        personal.add(try features(1), label: .tricepsPushdown)
        personal.add(try features(2), label: .tricepsPushdown)
        // Two sets aren't enough (they could be mislabelled curls)…
        XCTAssertLessThanOrEqual(GripModel.factor(for: .tricepsPushdown, features: set, body: .typical, personal: personal), 0.5 + 1e-6)
        personal.add(try features(3), label: .tricepsPushdown)
        // …three are.
        let after = GripModel.factor(for: .tricepsPushdown, features: set, body: .typical, personal: personal)
        XCTAssertLessThanOrEqual(before, 0.5 + 1e-6)
        XCTAssertGreaterThan(after, 0.95)
    }
}

final class ClassifierBlendTests: XCTestCase {
    func testModelCannotOutvoteExercisesItDoesNotKnow() {
        let prototype = [ExerciseCandidate(exercise: .tricepsPushdown, probability: 0.6),
                         ExerciseCandidate(exercise: .bicepCurl, probability: 0.3),
                         ExerciseCandidate(exercise: .frontRaise, probability: 0.1)]
        // The model has never seen a pushdown and calls it a curl.
        let model = [ExerciseCandidate(exercise: .bicepCurl, probability: 0.9),
                     ExerciseCandidate(exercise: .frontRaise, probability: 0.1)]
        let out = ClassifierBlend.combine(prototype: prototype, model: model,
                                          modelKnows: [.bicepCurl, .frontRaise, .lateralRaise], modelWeight: 0.65)
        XCTAssertEqual(out.first?.exercise, .tricepsPushdown)
        XCTAssertEqual(out.first?.probability ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertEqual(out.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)
        // Among the exercises it knows, the model still has its say.
        let curl = out.first { $0.exercise == .bicepCurl }?.probability ?? 0
        let raise = out.first { $0.exercise == .frontRaise }?.probability ?? 0
        XCTAssertGreaterThan(curl / raise, 3)
    }
}
