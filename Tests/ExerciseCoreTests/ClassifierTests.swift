import XCTest
@testable import ExerciseCore

final class ClassifierTests: XCTestCase {

    /// Exercises whose wrist motion is distinguishable in principle (pairs like lateral vs front raise,
    /// or bench press vs lat pulldown, look identical from the wrist and are checked via top-3).
    func testSimulatedExercisesAreRecognised() throws {
        var top1 = 0, top3 = 0, total = 0
        var report: [String] = []
        for exercise in RepDetectionTests.simulated {
            let samples = try XCTUnwrap(SyntheticMotion.generate(exercise))
            let a = SetAnalyzer().analyze(samples)
            let names = a.candidates.prefix(3).map { "\($0.exercise.rawValue) \(Int($0.probability * 100))%" }
            report.append("\(exercise.rawValue): \(names.joined(separator: ", "))")
            total += 1
            if a.candidates.first?.exercise == exercise { top1 += 1 }
            if a.candidates.prefix(3).contains(where: { $0.exercise == exercise }) { top3 += 1 }
        }
        print("Classifier on simulated sets – top1 \(top1)/\(total), top3 \(top3)/\(total)\n" + report.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(Double(top1) / Double(total), 0.6)
        XCTAssertGreaterThanOrEqual(Double(top3) / Double(total), 0.9)
    }

    func testDistinctiveExercisesAreTop1() throws {
        for exercise: ExerciseType in [.bicepCurl, .hammerCurl, .tricepsPushdown, .seatedCableRow, .chestPressMachine, .pecDeck] {
            let samples = try XCTUnwrap(SyntheticMotion.generate(exercise))
            let a = SetAnalyzer().analyze(samples)
            XCTAssertEqual(a.candidates.first?.exercise, exercise, "\(exercise) → \(a.candidates.prefix(3))")
        }
    }

    func testPersonalizationLearnsFromCorrections() throws {
        // Lateral and front raises look nearly identical from the wrist. After the user
        // labels a few front raises, the classifier should prefer front raise for that motion.
        var o = SyntheticMotion.Options()
        o.seed = 100
        let samples = try XCTUnwrap(SyntheticMotion.generate(.frontRaise, options: o))
        let signals = MotionSignals(samples: samples)
        let detection = try XCTUnwrap(RepDetector.detect(signals))
        let features = try XCTUnwrap(FeatureExtractor.extract(signals, detection: detection))

        var classifier = PrototypeExerciseClassifier()
        var personalization = ClassifierPersonalization()
        for seed in 1...4 {
            var oo = SyntheticMotion.Options()
            oo.seed = UInt64(seed)
            let s = try XCTUnwrap(SyntheticMotion.generate(.frontRaise, options: oo))
            let sig = MotionSignals(samples: s)
            let det = try XCTUnwrap(RepDetector.detect(sig))
            personalization.add(try XCTUnwrap(FeatureExtractor.extract(sig, detection: det)), label: .frontRaise)
        }
        classifier.personalization = personalization
        XCTAssertEqual(classifier.classify(features).first?.exercise, .frontRaise)
    }

    func testProbabilitiesSumToOne() throws {
        let samples = try XCTUnwrap(SyntheticMotion.generate(.shoulderPress))
        let a = SetAnalyzer().analyze(samples)
        XCTAssertEqual(a.candidates.reduce(0) { $0 + $1.probability }, 1, accuracy: 1e-9)
        XCTAssertFalse(a.candidates.contains { !$0.exercise.isAutoDetectable })
    }
}
