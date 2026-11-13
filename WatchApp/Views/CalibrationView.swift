import SwiftUI

/// Guided calibration: one instruction at a time. Each pose is detected automatically when the
/// arm becomes still in the right orientation; haptics confirm every step.
struct CalibrationView: View {
    @EnvironmentObject var app: WatchAppModel
    @ObservedObject var model: CalibrationViewModel

    private var finished: Bool { model.phase == .finished }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                stepDots
                BackgroundIssueBadge()
                if finished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Calibrated!")
                        .font(.headline)
                } else {
                    ZStack {
                        progressRing
                        Image(systemName: model.pose.symbolName)
                            .font(.system(size: 24))
                    }
                    .frame(width: 52, height: 52)
                    Text(model.pose.title)
                        .font(.headline)
                    // Status sits right under the title so it's visible without scrolling.
                    statusLine
                    if model.phoneIsShowingInstructions {
                        Label("Follow along on your iPhone", systemImage: "iphone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(model.pose.instruction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Skip") { model.skipStep() }
                        if app.calibration != nil {
                            Button("Use last") { app.useExistingCalibration() }
                        }
                    }
                    .font(.footnote)
                    Button("Cancel", role: .cancel) { app.cancelCalibration() }
                        .font(.footnote)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.stepIndex)
    }

    private var stepDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<CalibrationPose.allCases.count, id: \.self) { i in
                Circle()
                    .fill(i < model.stepIndex ? Color.green : (i == model.stepIndex ? Color.white : Color.gray.opacity(0.4)))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var holdProgress: Double {
        if case .holding(let p) = model.phase { return p }
        return 0
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.3), lineWidth: 5)
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.phase {
        case .waitingForMovement:
            Text("Move into position…").foregroundStyle(.orange).font(.footnote.bold())
        case .waitingForStillness:
            Text("Now hold still").foregroundStyle(.yellow).font(.footnote.bold())
        case .holding:
            Text("Holding…").foregroundStyle(.green).font(.footnote.bold())
        case .wrongPose(let message):
            Text(message).foregroundStyle(.red).font(.footnote.bold()).multilineTextAlignment(.center)
        case .finished:
            EmptyView()
        }
    }
}
