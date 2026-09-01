import AppKit
import SwiftUI

// MARK: - Theme

/// Dark values are lifted from the Claude Design mockup ("Remote Bindings"); light values keep the same
/// structure so the panel follows the system appearance. Both tabs draw from this.
enum PanelTheme {
    static let strip = Color.adaptive(light: 0xEAEAED, dark: 0x212124)
    static let paneTop = Color.adaptive(light: 0xE8E8EC, dark: 0x191A1C)
    static let paneBottom = Color.adaptive(light: 0xE1E1E5, dark: 0x141416)
    static let cardTop = Color.adaptive(light: 0xFFFFFF, dark: 0x232326)
    static let cardBottom = Color.adaptive(light: 0xF8F8FA, dark: 0x1F1F22)
    static let holdCard = Color.adaptive(light: 0xFAFAFC, dark: 0x1E1E21)
    static let pill = Color.adaptive(light: 0xE3E3E8, dark: 0x2C2C30)
    static let chip = Color.adaptive(light: 0xE6E6EA, dark: 0x26262A)
    static let keycapTop = Color.adaptive(light: 0xFFFFFF, dark: 0x3C3C41)
    static let keycapBottom = Color.adaptive(light: 0xECECEF, dark: 0x323236)
    static let hairline = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, alpha: 0.08)
    static let border = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, alpha: 0.11)
    static let secondary = Color.adaptive(light: 0x6E6E73, dark: 0x8B8B90)
    static let tertiary = Color.adaptive(light: 0x8E8E93, dark: 0x6F6F75)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: alpha))
    }

    static func adaptive(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: alpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
