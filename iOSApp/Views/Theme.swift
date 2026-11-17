import SwiftUI
import UIKit

/// The app's colours. The system green, orange and red are too light for text on white (about
/// 2:1 to 3.5:1; text needs 4.5:1), so text, icons and buttons use these darker shades in light mode
/// and brighter ones in dark mode. Each passes WCAG AA (4.5:1) on the app's backgrounds, including
/// the 15–20 % tinted fills behind badges and bordered buttons. Checked by the accessibility-audit
/// UI test.
extension Color {
    /// Rep Coach green: buttons, highlights, good scores. Also the app's accent colour (asset).
    static let brand = adaptive(light: 0x136B2D, dark: 0x3DD068)
    /// Text and icons on a brand-green fill (prominent buttons, the live-workout banner).
    static let onBrand = adaptive(light: 0xFFFFFF, dark: 0x00210B)
    /// Warnings, rest timers, "not quite" feedback.
    static let warning = adaptive(light: 0x8F4500, dark: 0xFFA94D)
    /// Destructive actions, errors, heart rate.
    static let danger = adaptive(light: 0xB3261E, dark: 0xFF7A70)
    /// Neutral information.
    static let info = adaptive(light: 0x0A58BA, dark: 0x5AB0FF)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension WorkoutRecord {
    /// "Bicep Curl, Shoulder Press, Lateral Raise + 2 more": short enough to show in full.
    func exerciseSummary(showing count: Int = 3) -> String {
        let names = exercises.map { $0.displayName }
        guard names.count > count else { return names.joined(separator: ", ") }
        return names.prefix(count).joined(separator: ", ") + " + \(names.count - count) more"
    }
}
