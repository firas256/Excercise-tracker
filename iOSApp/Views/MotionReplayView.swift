import Combine
import SwiftUI

/// Plays back a saved set as a 3-D arm animation, so you can check the watch saw the movement you did.
struct MotionReplayView: View {
    let recording: URL
    let reps: [RepMetrics]

    @State private var frames: [MotionFrame] = []
    @State private var loading = true
    @State private var time = 0.0
    @State private var playing = false
    @State private var speed = 1.0

    private let tick = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private var start: Double { frames.first?.t ?? 0 }
    private var end: Double { frames.last?.t ?? 0 }

    var body: some View {
        VStack(spacing: 10) {
            if loading {
                ProgressView().frame(height: 260)
            } else if frames.count < 2 {
                Text("This recording couldn't be read.").foregroundStyle(.secondary)
            } else {
                ArmMotionView(frames: frames, playbackTime: time)
                    .frame(height: 260)
                HStack(spacing: 12) {
                    Button {
                        if !playing, time >= end - 0.01 { time = start }
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 30)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    Slider(value: $time, in: start...max(end, start + 0.1), onEditingChanged: { editing in
                        if editing { playing = false }
                    })
                    .accessibilityLabel("Replay position")
                    Menu {
                        ForEach([0.5, 1.0, 2.0], id: \.self) { s in
                            Button(String(format: "%g×", s)) { speed = s }
                        }
                    } label: {
                        Text(String(format: "%g×", speed)).font(.subheadline.monospacedDigit()).frame(width: 36)
                    }
                    .accessibilityLabel("Playback speed")
                }
                HStack {
                    Text(String(format: "%.1f s", time - start)).monospacedDigit()
                    Spacer()
                    if let rep = currentRep {
                        Text("Rep \(rep.index)").bold()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .task(id: recording) { await load() }
        .onReceive(tick) { _ in
            guard playing else { return }
            time = min(end, time + speed / 30)
            if time >= end { playing = false }
        }
    }

    /// The rep being shown (rep times are seconds from the start of the recording).
    private var currentRep: RepMetrics? {
        let elapsed = time - start
        return reps.first { elapsed >= $0.startTime && elapsed < $0.startTime + $0.duration }
    }

    private func load() async {
        let url = recording
        let result = await Task.detached(priority: .userInitiated) { () -> [MotionFrame] in
            guard let csv = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return MotionFrameBuilder.frames(from: TrainingCSV.parse(csv), outputRate: 25)
        }.value
        frames = result
        time = result.first?.t ?? 0
        loading = false
        playing = result.count > 1
    }
}
