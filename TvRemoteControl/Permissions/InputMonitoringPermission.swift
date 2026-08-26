import AppKit
import Foundation
import IOKit.hid

enum InputMonitoringStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Input Monitoring (TCC "ListenEvent") gates reading HID input reports.
/// TCC keys the grant off the app's code signature, so re-signing invalidates it.
enum InputMonitoringPermission {
    static func status() -> InputMonitoringStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .notDetermined
        }
    }

    /// Shows the system prompt if the user hasn't decided yet. Returns immediately with the current
    /// state; the actual grant shows up on the next `status()` call.
    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
