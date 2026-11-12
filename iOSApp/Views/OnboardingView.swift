import SwiftUI

/// First launch: explains the app and requests every permission up front.
struct OnboardingView: View {
    @EnvironmentObject var health: HealthPermissionService
    @EnvironmentObject var connectivity: PhoneConnectivityService
    var onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            howItWorks.tag(1)
            permissions.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text("Rep Coach").font(.largeTitle.bold())
            Text("Your Apple Watch counts reps, recognises the exercise and coaches your range of motion and tempo – for free weights and machines.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { withAnimation { page = 1 } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer().frame(height: 40)
        }
        .padding(30)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("How it works").font(.largeTitle.bold())
            step("scope", "1. Calibrate", "Follow 5 quick poses on the watch. It buzzes when it detects each one, learning how the watch sits on your arm.")
            step("dumbbell.fill", "2. Lift", "Start your set. The accelerometer and gyroscope track each rep – the watch taps on every rep.")
            step("sparkles", "3. Auto-detect", "After a few reps the watch guesses the exercise. Correct it once and it learns your form.")
            step("chart.bar.fill", "4. Review", "See range of motion, tempo, consistency and fatigue for every set here on your iPhone.")
            Spacer()
            Button("Continue") { withAnimation { page = 2 } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 40)
        }
        .padding(30)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Permissions").font(.largeTitle.bold())
            Text("Rep Coach needs these to work properly. Everything is processed on your devices.")
                .foregroundStyle(.secondary)

            permissionRow(
                symbol: "heart.fill",
                title: "Apple Health",
                detail: "Runs a strength-training workout on the watch (keeps sensors on with your wrist down), reads heart rate and saves workouts.",
                granted: health.status == .requested,
                unavailable: health.status == .unavailable,
                action: { health.request() }
            )
            permissionRow(
                symbol: "applewatch",
                title: "Apple Watch",
                detail: connectivity.isWatchAppInstalled
                    ? "Watch app installed."
                    : (connectivity.isPaired ? "Install Rep Coach on your watch from the Watch app." : "Pair an Apple Watch to track workouts."),
                granted: connectivity.isWatchAppInstalled,
                unavailable: !connectivity.isSupported,
                action: nil
            )
            permissionRow(
                symbol: "gyroscope",
                title: "Motion sensors",
                detail: "The watch's accelerometer and gyroscope are used only during workouts. No extra prompt is needed.",
                granted: true,
                unavailable: false,
                action: nil
            )
            Spacer()
            Button("Get Started", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 40)
        }
        .padding(30)
        .onAppear { health.refresh() }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(symbol: String, title: String, detail: String, granted: Bool,
                               unavailable: Bool, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                if unavailable {
                    Text("Not available on this device").font(.caption).foregroundStyle(.orange)
                } else if granted {
                    Label("Done", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                } else if let action {
                    Button("Allow", action: action).buttonStyle(.bordered)
                }
            }
        }
    }
}
