import AppKit
import ApplicationServices
import Foundation

/// Accessibility (TCC "Accessibility") gates posting synthetic keyboard events.
enum AccessibilityPermission {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt if not yet trusted. Returns immediately; re-check via `isTrusted()`.
    @discardableResult
    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
