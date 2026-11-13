import SwiftUI

/// Small warning shown when the watch can't run a workout session: with the wrist down it then
/// can't tap or update the iPhone (watchOS only allows that during a running workout session).
/// Tap for the reason and the fix.
struct BackgroundIssueBadge: View {
    @EnvironmentObject var session: WorkoutSessionService
    var compact = false
    @State private var showDetails = false

    var body: some View {
        if let issue = session.backgroundIssue {
            Button {
                showDetails = true
            } label: {
                Label(compact ? "Wrist-down off" : "No taps with wrist down", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetails) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wrist-down mode is off").font(.headline)
                        Text("While your wrist is down the watch can't tap you or update your iPhone. Tracking itself carries on.")
                            .font(.footnote)
                        Text(issue).font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
