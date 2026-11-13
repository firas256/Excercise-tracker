import XCTest
@testable import ExerciseCore

final class LiveWorkoutTests: XCTestCase {

    func testCommandsAndStateRoundTrip() throws {
        let commands: [WatchCommand] = [
            .lockExercise(.bicepCurl), .lockExercise(nil), .endSet,
            .discardSet, .savePendingSet(id: UUID(), exercise: .shoulderPress, reps: 9, weight: 12.5),
            .discardPendingSet(id: UUID()), .endWorkout, .requestState,
        ]
        for c in commands {
            let data = try XCTUnwrap(PayloadCoding.encode(c))
            XCTAssertEqual(PayloadCoding.decode(WatchCommand.self, from: data), c)
        }
        var state = LiveWorkoutState.idle
        state.status = .reviewing
        state.candidates = [ExerciseCandidate(exercise: .bicepCurl, probability: 0.7)]
        state.pendingSet = PendingSetSummary(id: UUID(), exercise: .bicepCurl, candidates: state.candidates, repCount: 8,
                                             feedback: .empty, weight: 10, weightUnit: "kg")
        let data = try XCTUnwrap(PayloadCoding.encode(state))
        XCTAssertEqual(PayloadCoding.decode(LiveWorkoutState.self, from: data), state)
        XCTAssertEqual(state.currentGuess, .bicepCurl)
    }

    func testFramesFollowACurl() throws {
        var o = SyntheticMotion.Options()
        o.reps = 4
        let samples = try XCTUnwrap(SyntheticMotion.generate(.bicepCurl, options: o))
        let frames = MotionFrameBuilder.frames(from: samples, outputRate: 25)
        XCTAssertEqual(Double(frames.count), Double(samples.count) / 2, accuracy: 3)
        let elev = frames.map { $0.elevation }
        XCTAssertEqual(elev.min() ?? 0, -80, accuracy: 4)
        XCTAssertEqual(elev.max() ?? 0, 40, accuracy: 4)
        // A curl rotates in a vertical plane: heading stays put.
        XCTAssertLessThan(frames.map { abs($0.heading) }.max() ?? 0, 10)
        // Palm faces up mid-curl (forearm horizontal).
        let mid = try XCTUnwrap(frames.min { abs($0.elevation) < abs($1.elevation) })
        XCTAssertGreaterThan(mid.palmDirection.z, 0.8)
        XCTAssertGreaterThan(abs(mid.forearmDirection.z), -1)
    }

    func testFramesShowHorizontalSweepAndPressLift() throws {
        let deck = try XCTUnwrap(SyntheticMotion.generate(.pecDeck))
        let headings = MotionFrameBuilder.frames(from: deck).map { $0.heading }
        XCTAssertGreaterThan((headings.max() ?? 0) - (headings.min() ?? 0), 40)

        let press = try XCTUnwrap(SyntheticMotion.generate(.shoulderPress))
        let lifts = MotionFrameBuilder.frames(from: press).map { $0.lift }
        XCTAssertGreaterThan((lifts.max() ?? 0) - (lifts.min() ?? 0), 15)
    }
}
