import Foundation

/// Generates physically consistent arm-frame motion for a few exercises from a simple kinematic
/// model. Used by unit tests and to create the demo workout in the iPhone app.
enum SyntheticMotion {

    /// Arm orientation and hand position in the world (x forward, y left, z up).
    struct Pose {
        var forearm: Vector3
        var palm: Vector3
        var hand: Vector3
    }

    struct Options {
        var reps = 8
        var concentric = 1.2
        var eccentric = 2.0
        var pauseTop = 0.2
        var pauseBottom = 0.4
        /// Per-rep amplitude multipliers (1 = full range). Missing entries default to 1.
        var amplitudes: [Double] = []
        var noise = 0.02
        var stillLead = 1.5
        var stillTail = 1.0
        var sampleRate = 50.0
        var seed: UInt64 = 42
        /// Holds the weight with this grip instead of the exercise's usual one (e.g. a rope pushdown).
        var grip: Grip?
        /// Rests at the far end of the movement instead, e.g. a pushdown begun with the arms
        /// extended, so the reps "start" at the bottom like a curl.
        var restAtEnd = false
        /// Body size relative to the 0.3 m forearm / 0.6 m arm the movements are modelled on.
        var bodyScale = 1.0
    }

    /// Palm normal for a grip: rotated from palm-down about the forearm (thumb-up side positive).
    /// nil when the forearm is too close to vertical for "palm down" to mean anything.
    static func palm(for forearm: Vector3, grip: Grip) -> Vector3? {
        let f = forearm.normalized
        let down = Vector3(0, 0, -1).orthogonalized(against: f)
        guard down.length > 0.1 else { return nil }
        let pd = down.normalized
        let r = grip.nominalRoll * .pi / 180
        return pd * cos(r) + f.cross(pd) * sin(r)
    }

    private static func sagittal(_ deg: Double) -> Vector3 {
        let r = deg * .pi / 180
        return Vector3(cos(r), 0, sin(r))
    }

    /// Palm normal for a forearm in the sagittal plane, palm facing down when horizontal.
    private static func palmDownSagittal(_ deg: Double) -> Vector3 {
        let r = deg * .pi / 180
        return Vector3(sin(r), 0, -cos(r))
    }

    /// u = 0 at the resting position, 1 at the turnaround.
    static func kinematics(for exercise: ExerciseType) -> ((Double) -> Pose)? {
        switch exercise {
        case .bicepCurl:
            return { u in
                let th = -80 + 120 * u
                let r = th * .pi / 180
                let f = sagittal(th)
                return Pose(forearm: f, palm: Vector3(-sin(r), 0, cos(r)), hand: f * 0.3)
            }
        case .hammerCurl:
            return { u in
                let f = sagittal(-80 + 120 * u)
                return Pose(forearm: f, palm: Vector3(0, 1, 0), hand: f * 0.3)
            }
        case .lateralRaise:
            return { u in
                let r = (-85 + 82 * u) * .pi / 180
                let s = -1.0
                let f = Vector3(0, s * cos(r), sin(r))
                return Pose(forearm: f, palm: Vector3(0, s * sin(r), -cos(r)), hand: f * 0.6)
            }
        case .frontRaise:
            return { u in
                let th = -85 + 95 * u
                let f = sagittal(th)
                return Pose(forearm: f, palm: palmDownSagittal(th), hand: f * 0.6)
            }
        case .shoulderPress:
            return { u in
                let th = 65 + 20 * u
                return Pose(forearm: sagittal(th), palm: palmDownSagittal(th), hand: Vector3(0, 0, 0.42 * u))
            }
        case .benchPress:
            return { u in
                let th = 86 - 6 * u
                return Pose(forearm: sagittal(th), palm: palmDownSagittal(th), hand: Vector3(0, 0, -0.38 * u))
            }
        case .gobletSquat:
            return { u in
                Pose(forearm: sagittal(70), palm: palmDownSagittal(70), hand: Vector3(0, 0, -0.5 * u))
            }
        case .deadlift:
            return { u in
                Pose(forearm: sagittal(-88), palm: palmDownSagittal(-88), hand: Vector3(0.05 * u, 0, 0.5 * u))
            }
        case .seatedCableRow:
            return { u in
                Pose(forearm: sagittal(0), palm: Vector3(0, 1, 0), hand: Vector3(-0.35 * u, 0, 0))
            }
        case .chestPressMachine:
            return { u in
                Pose(forearm: sagittal(3), palm: palmDownSagittal(3), hand: Vector3(0.35 * u, 0, 0))
            }
        case .tricepsPushdown:
            return { u in
                let th = 15 - 90 * u
                let f = sagittal(th)
                return Pose(forearm: f, palm: palmDownSagittal(th), hand: f * 0.3)
            }
        case .latPulldown:
            return { u in
                let th = 82 - 8 * u
                return Pose(forearm: sagittal(th), palm: palmDownSagittal(th), hand: Vector3(0, 0, -0.45 * u))
            }
        case .pecDeck:
            return { u in
                let psi = 65 * u * .pi / 180
                let f0 = sagittal(80)
                let p0 = Vector3(0, 1, 0)
                func rz(_ v: Vector3) -> Vector3 {
                    Vector3(v.x * cos(psi) - v.y * sin(psi), v.x * sin(psi) + v.y * cos(psi), v.z)
                }
                let f = rz(f0)
                return Pose(forearm: f, palm: rz(p0), hand: rz(Vector3(0, -0.4, 0)) + f * 0.3)
            }
        default:
            return nil
        }
    }

    /// Phase u(t) for the whole set, plus total duration.
    private static func phaseTrack(_ o: Options, eccentricFirst: Bool) -> (Double) -> Double {
        let away = eccentricFirst ? o.eccentric : o.concentric
        let back = eccentricFirst ? o.concentric : o.eccentric
        let repLen = away + o.pauseTop + back + o.pauseBottom
        return { t in
            let local = t - o.stillLead
            guard local >= 0 else { return 0 }
            let k = Int(local / repLen)
            guard k < o.reps else { return 0 }
            let amp = k < o.amplitudes.count ? o.amplitudes[k] : 1
            let x = local - Double(k) * repLen
            func smooth(_ v: Double) -> Double { 0.5 - 0.5 * cos(.pi * SignalMath.clamp(v, 0, 1)) }
            if x < away { return amp * smooth(x / away) }
            if x < away + o.pauseTop { return amp }
            if x < away + o.pauseTop + back { return amp * (1 - smooth((x - away - o.pauseTop) / back)) }
            return 0
        }
    }

    static func duration(_ o: Options) -> Double {
        o.stillLead + Double(o.reps) * (o.concentric + o.eccentric + o.pauseTop + o.pauseBottom) + o.stillTail
    }

    /// Generates arm-frame samples for an exercise (nil if no kinematic model exists).
    static func generate(_ exercise: ExerciseType, options o: Options = Options()) -> [ArmSample]? {
        guard let base = kinematics(for: exercise) else { return nil }
        let kin: (Double) -> Pose = { u in
            var pose = base(o.restAtEnd ? 1 - u : u)
            pose.hand = pose.hand * o.bodyScale
            if let grip = o.grip, let palm = palm(for: pose.forearm, grip: grip) { pose.palm = palm }
            return pose
        }
        // Resting at the far end swaps which movement comes first (e.g. pushdown: up = eccentric).
        let u = phaseTrack(o, eccentricFirst: exercise.eccentricFirst != o.restAtEnd)
        let dt = 1 / o.sampleRate
        let n = Int(duration(o) * o.sampleRate)
        var rng = SeededRandom(seed: o.seed)

        func pose(_ t: Double) -> (f: Vector3, p: Vector3, r: Vector3, h: Vector3) {
            let ps = kin(u(t))
            let f = ps.forearm.normalized
            let p = ps.palm.orthogonalized(against: f).normalized
            return (f, p, f.cross(p).normalized, ps.hand)
        }

        var out: [ArmSample] = []
        out.reserveCapacity(n)
        let down = Vector3(0, 0, -1)
        for i in 0..<n {
            let t = Double(i) * dt
            let a = pose(t - dt), b = pose(t), c = pose(t + dt)
            // Angular velocity from frame derivatives: 2ω = Σ e_i × ė_i.
            let df = (c.f - a.f) / (2 * dt), dp = (c.p - a.p) / (2 * dt), dr = (c.r - a.r) / (2 * dt)
            let omega = (b.f.cross(df) + b.p.cross(dp) + b.r.cross(dr)) * 0.5
            let acc = (c.h - b.h * 2 + a.h) / (dt * dt) / 9.80665
            func arm(_ v: Vector3) -> Vector3 { Vector3(v.dot(b.f), v.dot(b.p), v.dot(b.r)) }
            let noiseG = Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * (o.noise * 0.1)
            let noiseA = Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * o.noise
            let noiseW = Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * (o.noise * 2)
            out.append(ArmSample(
                t: t,
                gravity: (arm(down) + noiseG).normalized,
                acceleration: arm(acc) + noiseA,
                rotation: arm(omega) + noiseW
            ))
        }
        return out
    }
}

/// Deterministic random numbers (SplitMix64) so tests and demo data are reproducible.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func gaussian() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// A physically consistent calibration routine: a straight arm of a given length pivoting at the
/// shoulder through the five poses, with smooth moves between them. Used by tests and by the
/// Simulator's scripted motion.
enum SyntheticCalibration {
    struct Pose { var forearm: Vector3; var palm: Vector3 }

    /// The five calibration poses in the world (x forward, y left, z up).
    static func poses(overheadElevation: Double = 90) -> [Pose] {
        let oh = overheadElevation * .pi / 180
        return [
            Pose(forearm: Vector3(0, 0, -1), palm: Vector3(0, 1, 0)),   // arms down, palm to thigh
            Pose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, -1)),   // forward, palm down
            Pose(forearm: Vector3(1, 0, 0), palm: Vector3(0, 0, 1)),    // forward, palm up
            Pose(forearm: Vector3(0, 1, 0), palm: Vector3(0, 0, -1)),   // side, palm down
            Pose(forearm: Vector3(0, cos(oh), sin(oh)), palm: Vector3(-1, 0, 0)),  // overhead
        ]
    }

    /// - Parameters:
    ///   - armLength: shoulder → watch (m).
    ///   - deliveredSign: CoreMotion delivers userAcceleration as the *negative* of the physical one (-1).
    ///   - lead: optional pose held before the routine (e.g. arm raised, reading the watch).
    static func samples(armLength: Double = 0.6, deliveredSign: Double = -1, rate: Double = 50,
                        hold: Double = 2.5, move: Double = 1.2, lead: Pose? = nil, leadSeconds: Double = 2.5,
                        overheadElevation: Double = 90, wearing: CalibrationProfile = .defaultProfile(),
                        noiseSeed: UInt64? = nil) -> [MotionSample] {
        let f = wearing.forearmAxis, p = wearing.palmAxis, r = wearing.radialAxis
        var poses = self.poses(overheadElevation: overheadElevation)
        if let lead { poses.insert(lead, at: 0) }
        let dt = 1 / rate
        // Timeline of (from pose, to pose, eased fraction).
        var timeline: [(Int, Int, Double)] = []
        for _ in 0..<Int((lead != nil ? leadSeconds : hold) * rate) { timeline.append((0, 0, 0)) }
        for i in 1..<poses.count {
            for k in 0..<Int(move * rate) {
                let u = Double(k) / (move * rate)
                timeline.append((i - 1, i, 0.5 - 0.5 * cos(.pi * u)))
            }
            for _ in 0..<Int(hold * rate) { timeline.append((i, i, 0)) }
        }
        // Back to arms down at the end, as people do.
        for k in 0..<Int(move * rate) {
            timeline.append((poses.count - 1, lead != nil ? 1 : 0, 0.5 - 0.5 * cos(.pi * Double(k) / (move * rate))))
        }
        for _ in 0..<Int(hold * rate) { timeline.append((lead != nil ? 1 : 0, lead != nil ? 1 : 0, 0)) }

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
        var rng = SeededRandom(seed: noiseSeed ?? 0)
        var out: [MotionSample] = []
        out.reserveCapacity(timeline.count)
        for i in 0..<timeline.count {
            let (fa, pa, ra) = frame(i - 1), (fb, pb, rb) = frame(i), (fc, pc, rc) = frame(i + 1)
            var omega = (fb.cross((fc - fa) / (2 * dt)) + pb.cross((pc - pa) / (2 * dt)) + rb.cross((rc - ra) / (2 * dt))) * 0.5
            // The watch sits at armLength along the straight arm.
            var accel = (fc * armLength - fb * (2 * armLength) + fa * armLength) / (dt * dt) / 9.80665
            if noiseSeed != nil {
                omega += Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.02
                accel += Vector3(rng.gaussian(), rng.gaussian(), rng.gaussian()) * 0.005
            }
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
}
