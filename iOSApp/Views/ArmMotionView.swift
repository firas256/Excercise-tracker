import SwiftUI

/// 3-D view of the watch arm: the forearm (green) with the watch on the wrist, the palm direction
/// (orange arrow) and the path of the hand over the last seconds. The camera switches between a
/// 3-D, side and front view (buttons rather than dragging, so the screen around it still scrolls).
///
/// Live mode follows the newest frames from the watch (slightly delayed and interpolated so the
/// animation is smooth); replay mode shows the frame at `playbackTime`.
struct ArmMotionView: View {
    let frames: [MotionFrame]
    /// Frame time to show; nil = live.
    var playbackTime: Double?
    /// When the newest frame arrived (live mode).
    var lastArrival: Date?
    /// The user's forearm (elbow → watch, m) from calibration: one drawn forearm length.
    var forearmLength: Double = MotionFrameBuilder.defaultWatchRadius

    enum Camera: String, CaseIterable, Identifiable {
        case threeD = "3D", side = "Side", front = "Front"
        var id: String { rawValue }
        /// (yaw, pitch) in degrees.
        var angles: (Double, Double) {
            switch self {
            case .threeD: return (-35, 18)
            case .side: return (0, 4)
            case .front: return (90, 4)
            }
        }
    }

    @State private var camera = Camera.threeD
    /// `-stillAnimations YES` (accessibility-audit UI test): nothing animates, so the audit can finish.
    static let stillForTests = UserDefaults.standard.bool(forKey: "stillAnimations")
    private var yaw: Double { camera.angles.0 }
    private var pitch: Double { camera.angles.1 }

    private let liveDelay = 0.35
    private let trailSeconds = 2.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playbackTime != nil || Self.stillForTests)) { timeline in
            let t = displayTime(now: timeline.date)
            let frame = t.flatMap { interpolated(at: $0) }
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, size in draw(&ctx, size: size, time: t, frame: frame) }
                    .accessibilityHidden(true)
                if let frame {
                    Text("Forearm \(Int(frame.elevation.rounded()))°  ·  Wrist \(frame.lift >= 0 ? "+" : "")\(Int(frame.lift.rounded())) cm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(10)
                } else {
                    Text("Waiting for motion from your watch…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Picker("View", selection: $camera) {
                ForEach(Camera.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            .padding(8)
        }
    }

    // MARK: Timing & interpolation

    private func displayTime(now: Date) -> Double? {
        if let playbackTime { return playbackTime }
        guard let last = frames.last else { return nil }
        let sinceArrival = lastArrival.map { now.timeIntervalSince($0) } ?? 0
        let t = last.t - liveDelay + min(liveDelay, max(0, sinceArrival))
        return max(frames.first?.t ?? t, t)
    }

    private func interpolated(at t: Double) -> MotionFrame? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if t <= first.t { return first }
        if t >= last.t { return last }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frames[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = frames[lo], b = frames[hi]
        let u = (t - a.t) / max(b.t - a.t, 1e-6)
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * u }
        var dRoll = b.roll - a.roll
        if dRoll > 180 { dRoll -= 360 }
        if dRoll < -180 { dRoll += 360 }
        return MotionFrame(t: t, elevation: lerp(a.elevation, b.elevation), heading: lerp(a.heading, b.heading),
                           roll: a.roll + dRoll * u, lift: lerp(a.lift, b.lift), elbowLift: lerp(a.elbowLift, b.elbowLift))
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double?, frame: MotionFrame?) {
        let unit = min(size.width, size.height) * 0.3
        let center = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let yr = yaw * .pi / 180, pr = pitch * .pi / 180
        func project(_ p: Vector3) -> CGPoint {
            let sx = p.x * cos(yr) + p.y * sin(yr)
            let depth = -p.x * sin(yr) + p.y * cos(yr)
            let sy = p.z * cos(pr) + depth * sin(pr)
            return CGPoint(x: center.x + sx * unit, y: center.y - sy * unit)
        }
        // The elbow moves only by what the forearm's rotation doesn't explain (a press, a squat);
        // one unit = the user's forearm length.
        let unitCM = max(15, forearmLength * 100)
        func liftOffset(_ f: MotionFrame) -> Vector3 {
            Vector3(0, 0, max(-1.2, min(1.2, f.elbowLift / unitCM)))
        }

        // Floor grid and vertical reference
        var grid = Path()
        for i in stride(from: -1.2, through: 1.21, by: 0.4) {
            grid.move(to: project(Vector3(i, -1.2, -1.3))); grid.addLine(to: project(Vector3(i, 1.2, -1.3)))
            grid.move(to: project(Vector3(-1.2, i, -1.3))); grid.addLine(to: project(Vector3(1.2, i, -1.3)))
        }
        ctx.stroke(grid, with: .color(.gray.opacity(0.2)), lineWidth: 1)
        var axis = Path()
        axis.move(to: project(Vector3(0, 0, -1.3))); axis.addLine(to: project(Vector3(0, 0, 1.3)))
        ctx.stroke(axis, with: .color(.gray.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        // "Forward" marker on the floor
        ctx.draw(Text("forward").font(.caption2).foregroundStyle(.secondary), at: project(Vector3(1.35, 0, -1.3)))

        guard let frame, let time else { return }

        // Hand trail
        let trail = frames.filter { $0.t >= time - trailSeconds && $0.t <= time }
        if trail.count > 1 {
            for i in 1..<trail.count {
                let a = trail[i - 1], b = trail[i]
                var seg = Path()
                seg.move(to: project(liftOffset(a) + a.forearmDirection))
                seg.addLine(to: project(liftOffset(b) + b.forearmDirection))
                let age = (time - b.t) / trailSeconds
                ctx.stroke(seg, with: .color(.green.opacity(0.6 * (1 - age))), lineWidth: 3)
            }
        }

        let elbow = liftOffset(frame)
        let hand = elbow + frame.forearmDirection
        // Shadow on the floor
        var shadow = Path()
        shadow.move(to: project(Vector3(elbow.x, elbow.y, -1.3))); shadow.addLine(to: project(Vector3(hand.x, hand.y, -1.3)))
        ctx.stroke(shadow, with: .color(.black.opacity(0.12)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        // Forearm
        var arm = Path()
        arm.move(to: project(elbow)); arm.addLine(to: project(hand))
        ctx.stroke(arm, with: .color(.green), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        // Elbow
        let e = project(elbow)
        ctx.fill(Path(ellipseIn: CGRect(x: e.x - 9, y: e.y - 9, width: 18, height: 18)), with: .color(.gray))
        // Watch on the wrist
        let w = project(elbow + frame.forearmDirection * 0.8)
        ctx.fill(Path(roundedRect: CGRect(x: w.x - 9, y: w.y - 9, width: 18, height: 18), cornerRadius: 4), with: .color(.primary))
        // Palm direction
        let h = project(hand)
        let tip = project(hand + frame.palmDirection * 0.35)
        var palm = Path()
        palm.move(to: h); palm.addLine(to: tip)
        ctx.stroke(palm, with: .color(.orange), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(.orange))
    }
}
