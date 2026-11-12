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
        score >= 85 ? .green : (score >= 65 ? .yellow : .orange)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.green)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
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
        case .positive: return .green
        case .warning: return .orange
        case .info: return .blue
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
        case .good: return .green
        case .moderate: return .blue
        case .limited: return .orange
        }
    }
}

extension TimeInterval {
    var minutesSeconds: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
