import CoreMotion
import Foundation

/// Streams fused device-motion (gravity, user acceleration, rotation rate, attitude) at ~50 Hz.
/// Callbacks arrive on `queue`, a serial background queue shared by all motion processing.
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

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    private(set) var isRunning = false

    /// Starts updates, replacing any previous handler.
    func start(rate: Double = 50, handler: @escaping (MotionSample) -> Void) {
        queue.async { self.handler = handler }
        guard manager.isDeviceMotionAvailable else { return }
        if isRunning { return }
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
        manager.stopDeviceMotionUpdates()
        isRunning = false
        queue.async { self.handler = nil }
    }
}
