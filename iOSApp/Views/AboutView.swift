import SwiftUI

/// Where the app's public pages live. The privacy policy and support pages are in the repository's
/// docs/ folder, published with GitHub Pages (repository Settings › Pages › branch, /docs).
enum AppInfo {
    static let privacyPolicyURL = URL(string: "https://firas256.github.io/Excercise-tracker/privacy-policy")!
    static let supportURL = URL(string: "https://firas256.github.io/Excercise-tracker/support")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

/// Privacy summary, health & safety notes and credits for the data the exercise model learned from.
struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: AppInfo.version)
            }

            Section {
                point("iphone.and.arrow.forward", "Your workouts, motion recordings, calibration and settings stay on your iPhone and Apple Watch. They sync directly between your two devices.")
                point("heart.text.square", "With your permission, workouts are saved to Apple Health, and heart rate and active energy are read from it during workouts. Health data is never used for advertising and never leaves Apple Health through this app.")
                point("hand.raised", "No account, no ads, no analytics, no tracking. Nothing is sent to the developer or anyone else.")
                point("trash", "Delete your workouts or recordings any time in Settings; deleting the app removes everything it stored on your devices. Workouts already saved to Apple Health stay there until you delete them in the Health app.")
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("Full privacy policy", systemImage: "doc.text")
                }
            } header: {
                Text("Your privacy")
            }

            Section {
                point("exclamationmark.triangle", "Rep Coach is a training aid, not a medical device. Rep counts, exercise guesses, form tips and body measurements are estimates from the watch's motion sensors and can be wrong.")
                point("figure.cooldown", "Stop if anything hurts, use weights you can control, and ask a qualified coach or health professional about your training, especially after an injury.")
            } header: {
                Text("Health & safety")
            }

            Section {
                credit("RecoFit", "The exercise model learned from Microsoft Research's RecoFit recordings (Morris et al., CHI 2014), CDLA-Permissive-2.0.",
                       URL(string: "https://github.com/microsoft/Exercise-Recognition-from-Wearable-Sensors"))
                credit("Body proportions", "Forearm, upper arm and height are estimated from arm length using standard anthropometric segment ratios (Drillis & Contini).", nil)
            } header: {
                Text("Credits")
            }

            Section {
                Link(destination: AppInfo.supportURL) {
                    Label("Help & support", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("Privacy, safety & credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.brand).accessibilityHidden(true)
        }
    }

    private func credit(_ title: String, _ text: String, _ url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.caption).foregroundStyle(.secondary)
            if let url {
                Link("Source", destination: url).font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
