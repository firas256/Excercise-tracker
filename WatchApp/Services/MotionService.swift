import CoreMotion
import Foundation

/// Streams fused device-motion (gravity, user acceleration, rotation rate, attitude) at ~50 Hz.
/// Callbacks arrive on `queue`, a serial background queue shared by all motion processing.
///
/// In the Simulator (which has no motion sensors) it plays `MotionScript` instead, so the whole
/// app can be tried and UI-tested. Launch arguments: `-simulateMotion NO` disables this,
/// `-simulationSpeed 3` plays it faster.
final class MotionService {
    static let shared = MotionService()

    let queue = DispatchQueue(label: "exercise-tracker.motion", qos: .userInitiated)
    private let manager = CMMotionManager()
    private lazy var operationQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.underlyingQueue = queue
        q.name = "exercise-tracker.motion.ops"
        return q
    }()
    private var handler: ((MotionSample) -> Void)?
    private var simulationTimer: DispatchSourceTimer?

    /// Which script the Simulator plays next time `start` is called.
    var simulationScenario: MotionScript.Scenario = .workout

    static var isSimulating: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.object(forKey: "simulateMotion") as? Bool ?? true
        #else
        return false
        #endif
    }

    var isAvailable: Bool { Self.isSimulating || manager.isDeviceMotionAvailable }
    private(set) var isRunning = false

    /// Starts updates, replacing any previous handler.
    func start(rate: Double = 50, handler: @escaping (MotionSample) -> Void) {
        queue.async { self.handler = handler }
        if isRunning { return }
        if Self.isSimulating {
            startSimulation(rate: rate)
            return
        }
        guard manager.isDeviceMotionAvailable else { return }
        isRunning = true
        manager.deviceMotionUpdateInterval = 1.0 / rate
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xArbitraryCorrectedZVertical)
            ? .xArbitraryCorrectedZVertical : .xArbitraryZVertical
        manager.startDeviceMotionUpdates(using: frame, to: operationQueue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let g = m.gravity, a = m.userAcceleration, r = m.rotationRate, q = m.attitude.quaternion
            let sample = MotionSample(
                timestamp: m.timestamp,
                gravity: Vector3(g.x, g.y, g.z),
                userAcceleration: Vector3(a.x, a.y, a.z),
                rotationRate: Vector3(r.x, r.y, r.z),
                attitude: Quaternion(x: q.x, y: q.y, z: q.z, w: q.w)
            )
            self.handler?(sample)
        }
    }

    func stop() {
        if Self.isSimulating {
            queue.async {
                self.simulationTimer?.cancel()
                self.simulationTimer = nil
                self.handler = nil
            }
        } else {
            manager.stopDeviceMotionUpdates()
            queue.async { self.handler = nil }
        }
        isRunning = false
    }

    /// Plays the motion script at `rate` (× simulationSpeed). Timer state lives on `queue`.
    private func startSimulation(rate: Double) {
        isRunning = true
        let scenario = simulationScenario
        // Calibration always plays in real time so each pose can be followed on screen.
        let requested = max(1, Int(UserDefaults.standard.double(forKey: "simulationSpeed").rounded()))
        let speed = scenario == .calibration ? 1 : requested
        queue.async {
            self.simulationTimer?.cancel()
            let script = MotionScript.samples(for: scenario, rate: rate)
            guard let last = script.last else { return }
            let loopLength = last.timestamp + 1 / rate
            var index = 0
            var offset = 0.0
            var emitted = 0
            let started = DispatchTime.now().uptimeNanoseconds
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1 / rate)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                // Follow the wall clock (and catch up if ticks arrive late on a busy machine), so the
                // script plays at the intended speed.
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
                let due = Int(elapsed * rate * Double(speed)) + 1
                for _ in 0..<min(max(0, due - emitted), Int(rate) * speed) {
                    var sample = script[index]
                    sample.timestamp += offset
                    self.handler?(sample)
                    emitted += 1
                    index += 1
                    if index == script.count {
                        index = 0
                        offset += loopLength
                    }
                }
            }
            timer.resume()
            self.simulationTimer = timer
        }
    }
}
