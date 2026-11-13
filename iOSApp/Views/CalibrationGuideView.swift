import AVFoundation
import SwiftUI
import UIKit

/// Full-screen guide shown while the watch calibrates: you can't read the watch with your arm
/// raised, so the phone shows (and speaks) each instruction, live, as the watch detects the poses.
struct CalibrationGuideView: View {
    @EnvironmentObject var connectivity: PhoneConnectivityService
    @StateObject private var speech = GuideSpeaker()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let state = connectivity.liveCalibration {
                content(state)
                    .onAppear { speech.announce(state, previous: nil) }
                    .onChange(of: state) { old, new in speech.announce(new, previous: old) }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speech.stop()
        }
    }

    private func content(_ state: CalibrationLiveState) -> some View {
        VStack(spacing: 18) {
            HStack {
                Label("Calibrating on Apple Watch", systemImage: "applewatch")
                    .font(.headline)
                Spacer()
                Button {
                    speech.isMuted.toggle()
                } label: {
                    Image(systemName: speech.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(speech.isMuted ? "Unmute instructions" : "Mute instructions")
                Button {
                    connectivity.liveCalibration = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .accessibilityLabel("Close")
            }
            .foregroundStyle(.secondary)

            if let issue = state.backgroundIssue {
                WatchBackgroundIssueBanner(issue: issue)
            }

            stepDots(state)

            if state.status == .finished {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(.green)
                Text("Calibrated!").font(.largeTitle.bold())
                Text("You're ready to lift. Start your first set whenever you like.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: state.status == .holding ? state.progress : 0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.25), value: state.progress)
                    PoseFigure(pose: state.pose)
                        .padding(36)
                }
                .frame(maxWidth: 300, maxHeight: 300)

                Text(state.pose.title)
                    .font(.largeTitle.bold())
                Text(state.pose.instruction)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                statusPill(state)
                Spacer(minLength: 0)
                Text("The watch notices each pose by itself and taps your wrist when it's captured.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.25), value: state.step)
    }

    private func stepDots(_ state: CalibrationLiveState) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<state.totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i < state.step || state.status == .finished ? Color.green
                          : (i == state.step ? Color.primary : Color.gray.opacity(0.3)))
                    .frame(width: i == state.step ? 28 : 10, height: 10)
            }
        }
        .accessibilityLabel("Step \(min(state.step + 1, state.totalSteps)) of \(state.totalSteps)")
    }

    @ViewBuilder private func statusPill(_ state: CalibrationLiveState) -> some View {
        let (text, color): (String, Color) = {
            switch state.status {
            case .moveIntoPosition: return ("Move into position…", .orange)
            case .holdStill: return ("Now hold still", .yellow)
            case .holding: return ("Holding… \(Int(state.progress * 100))%", .green)
            case .wrongPose: return (state.message ?? "Adjust your arm", .red)
            case .finished, .cancelled: return ("", .clear)
            }
        }()
        Text(text)
            .font(.title2.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color == .yellow ? Color.orange : color)
            .multilineTextAlignment(.center)
    }
}

/// Speaks the instructions so you don't have to look at any screen.
final class GuideSpeaker: ObservableObject {
    private static let mutedKey = "guideSpeechMuted"
    /// Remembered between calibrations (the speaker button on the guide).
    @Published var isMuted = UserDefaults.standard.bool(forKey: GuideSpeaker.mutedKey) {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
            if isMuted { stop() }
        }
    }
    private let synthesizer = AVSpeechSynthesizer()

    func announce(_ state: CalibrationLiveState, previous: CalibrationLiveState?) {
        if previous == nil || previous?.step != state.step, state.status != .finished {
            say(state.pose.spokenInstruction)
        } else if state.status == .wrongPose, previous?.status != .wrongPose, let message = state.message {
            say(message)
        } else if state.status == .finished, previous?.status != .finished {
            say("Calibration complete. You're ready to lift.")
        }
    }

    func say(_ text: String) {
        guard !isMuted else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// Simple stick figure showing where to put the watch arm (green, with the watch on the wrist).
struct PoseFigure: View {
    let pose: CalibrationPose

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 240
            func p(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: size.width / 2 + (x - 120) * s, y: size.height / 2 + (y - 120) * s)
            }
            let body = GraphicsContext.Shading.color(.primary.opacity(0.75))
            let accent = GraphicsContext.Shading.color(.green)
            let line = StrokeStyle(lineWidth: 9 * s, lineCap: .round, lineJoin: .round)
            let front = pose == .armSide
            let shoulder = front ? p(132, 85) : p(120, 85)

            // Head, torso, legs
            ctx.fill(Path(ellipseIn: CGRect(origin: p(104, 40), size: CGSize(width: 32 * s, height: 32 * s))), with: body)
            var torso = Path()
            torso.move(to: p(120, 78)); torso.addLine(to: p(120, 155))
            torso.move(to: p(120, 155)); torso.addLine(to: p(front ? 102 : 110, 225))
            torso.move(to: p(120, 155)); torso.addLine(to: p(front ? 138 : 130, 225))
            ctx.stroke(torso, with: body, style: line)
            // Other arm (hanging)
            var other = Path()
            if front {
                other.move(to: p(108, 85)); other.addLine(to: p(100, 150))
            } else {
                other.move(to: p(120, 85)); other.addLine(to: p(112, 150))
            }
            ctx.stroke(other, with: .color(.primary.opacity(0.3)), style: line)

            // Watch arm
            let hand: CGPoint
            switch pose {
            case .armsDown: hand = p(124, 155)
            case .armForward, .palmUp: hand = p(195, 85)
            case .armSide: hand = p(205, 85)
            case .armOverhead: hand = p(120, 10)
            }
            var arm = Path()
            arm.move(to: shoulder); arm.addLine(to: hand)
            ctx.stroke(arm, with: accent, style: line)
            // Watch on the wrist (85% along the arm)
            let wrist = CGPoint(x: shoulder.x + (hand.x - shoulder.x) * 0.82, y: shoulder.y + (hand.y - shoulder.y) * 0.82)
            let w = 14 * s
            ctx.fill(Path(roundedRect: CGRect(x: wrist.x - w / 2, y: wrist.y - w / 2, width: w, height: w), cornerRadius: 3 * s),
                     with: .color(.primary))
            // Palm direction arrow for the horizontal poses
            if pose == .armForward || pose == .palmUp || pose == .armSide {
                let up = pose == .palmUp
                let base = CGPoint(x: hand.x, y: hand.y + (up ? -10 : 10) * s)
                let tip = CGPoint(x: hand.x, y: hand.y + (up ? -34 : 34) * s)
                var arrow = Path()
                arrow.move(to: base); arrow.addLine(to: tip)
                arrow.move(to: CGPoint(x: tip.x - 7 * s, y: tip.y + (up ? 8 : -8) * s)); arrow.addLine(to: tip)
                arrow.addLine(to: CGPoint(x: tip.x + 7 * s, y: tip.y + (up ? 8 : -8) * s))
                ctx.stroke(arrow, with: .color(.orange), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round, lineJoin: .round))
                ctx.draw(Text(up ? "palm up" : "palm down").font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(.orange),
                         at: CGPoint(x: hand.x - 30 * s, y: tip.y), anchor: .center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
