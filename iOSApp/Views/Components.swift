import SwiftUI

struct ScoreBadge: View {
    let score: Int
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.25), lineWidth: size / 9)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(Self.color(for: score), style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Score \(score) out of 100")
    }

    static func color(for score: Int) -> Color {
        score >= 85 ? Color.brand : (score >= 65 ? .yellow : .orange)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Color.brand).accessibilityHidden(true)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct FeedbackTipRow: View {
    let tip: FeedbackTip

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(.subheadline.bold())
                Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch tip.kind {
        case .positive: return "hand.thumbsup.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch tip.kind {
        case .positive: return .brand
        case .warning: return .warning
        case .info: return .info
        }
    }
}

struct TrackingQualityBadge: View {
    let quality: TrackingQuality

    var body: some View {
        Text(quality.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch quality {
        case .good: return .brand
        case .moderate: return .info
        case .limited: return .warning
        }
    }
}

extension TimeInterval {
    var minutesSeconds: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The watch couldn't start a workout session, so with the wrist down it can't tap or send live
/// updates (watchOS only allows that during a running workout session). Explains why and how to fix.
struct WatchBackgroundIssueBanner: View {
    let issue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Your watch pauses when your wrist is down", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
            Text("No taps and no live updates here until you raise your wrist – the watch keeps recording. \(issue)")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.warning)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
