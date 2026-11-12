import Foundation

/// Derived 1-D signals computed from a buffer of arm-frame samples.
struct MotionSignals {
    let samples: [ArmSample]
    let dt: Double
    /// Forearm elevation (deg).
    let elevation: [Double]
    /// Dominant rotation axis (arm frame) for this buffer.
    let rotationAxis: Vector3?
    /// Angular rate about the dominant axis (deg/s).
    let rotationRate: [Double]
    /// Integrated rotation about the dominant axis (deg), high-passed without phase shift.
    let rotation: [Double]
    /// Vertical acceleration (m/s², up positive).
    let verticalAcceleration: [Double]
    /// Double-integrated vertical position (cm), zero-phase high-passed. Amplitudes use zero-velocity updates.
    let vertical: [Double]
    /// Acceleration along the forearm (m/s²).
    let forearmAcceleration: [Double]
    /// Double-integrated position along the forearm (cm), zero-phase high-passed.
    let forearm: [Double]
    /// Angular rate about world vertical (deg/s).
    let yawRate: [Double]

    init(samples: [ArmSample], nominalRate: Double = 50) {
        self.samples = samples
        if samples.count > 1, let first = samples.first, let last = samples.last, last.t > first.t {
            dt = (last.t - first.t) / Double(samples.count - 1)
        } else {
            dt = 1 / nominalRate
        }
        let deg = 180 / Double.pi
        elevation = samples.map { $0.elevation }

        let rotations = samples.map { $0.rotation }
        // Orient the principal axis consistently (largest absolute component positive).
        if var axis = SignalMath.principalAxis(rotations) {
            let comps = [axis.x, axis.y, axis.z]
            if let maxComp = comps.max(by: { abs($0) < abs($1) }), maxComp < 0 { axis = -axis }
            rotationAxis = axis
            rotationRate = rotations.map { $0.dot(axis) * deg }
        } else {
            rotationAxis = nil
            rotationRate = [Double](repeating: 0, count: samples.count)
        }
        let window = Int(5 / dt) | 1
        rotation = SignalMath.zeroPhaseIntegrate(rotationRate, dt: dt, window: window)

        verticalAcceleration = samples.map { $0.verticalAcceleration }
        vertical = SignalMath.zeroPhaseIntegrate(
            SignalMath.zeroPhaseIntegrate(verticalAcceleration, dt: dt, window: window), dt: dt, window: window
        ).map { $0 * 100 }

        forearmAcceleration = samples.map { $0.forearmAcceleration }
        forearm = SignalMath.zeroPhaseIntegrate(
            SignalMath.zeroPhaseIntegrate(forearmAcceleration, dt: dt, window: window), dt: dt, window: window
        ).map { $0 * 100 }

        yawRate = samples.map { $0.yawRate * deg }
    }

    var count: Int { samples.count }

    func series(_ kind: RepSignalKind) -> [Double] {
        switch kind {
        case .elevation: return elevation
        case .rotation: return rotation
        case .vertical: return vertical
        case .forearm: return forearm
        }
    }

    /// Plain (not high-passed) integral of the signal. Drifts over long spans, but is faithful over
    /// the first few seconds, which is what we need to tell the resting side from the first movement.
    func rawSeries(_ kind: RepSignalKind) -> [Double] {
        func cumulative(_ x: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: x.count)
            var acc = 0.0
            for i in 0..<x.count {
                acc += x[i] * dt
                out[i] = acc
            }
            return out
        }
        switch kind {
        case .elevation: return elevation
        case .rotation: return cumulative(rotationRate)
        case .vertical: return cumulative(cumulative(verticalAcceleration))
        case .forearm: return cumulative(cumulative(forearmAcceleration))
        }
    }

    /// Range of motion between two indices for the given signal, in that signal's unit.
    /// Translation uses zero-velocity-update integration (velocity is ~0 at rep turnarounds).
    func range(_ kind: RepSignalKind, from a: Int, to b: Int) -> Double {
        guard a >= 0, b < count, b > a else { return 0 }
        switch kind {
        case .elevation:
            return abs(elevation[b] - elevation[a])
        case .rotation:
            return abs(SignalMath.integrate(rotationRate, from: a, to: b + 1, dt: dt))
        case .vertical:
            return abs(SignalMath.zeroVelocityDisplacement(verticalAcceleration, from: a, to: b + 1, dt: dt)) * 100
        case .forearm:
            return abs(SignalMath.zeroVelocityDisplacement(forearmAcceleration, from: a, to: b + 1, dt: dt)) * 100
        }
    }

    /// Signed vertical displacement (cm) between two indices.
    func verticalDisplacement(from a: Int, to b: Int) -> Double {
        SignalMath.zeroVelocityDisplacement(verticalAcceleration, from: a, to: b + 1, dt: dt) * 100
    }

    /// Signed displacement along the forearm (cm) between two indices.
    func forearmDisplacement(from a: Int, to b: Int) -> Double {
        SignalMath.zeroVelocityDisplacement(forearmAcceleration, from: a, to: b + 1, dt: dt) * 100
    }

    /// Absolute rotation (deg) about world vertical between two indices.
    func yawRange(from a: Int, to b: Int) -> Double {
        abs(SignalMath.integrate(yawRate, from: a, to: b + 1, dt: dt))
    }
}
