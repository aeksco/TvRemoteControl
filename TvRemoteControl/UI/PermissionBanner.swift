import SwiftUI

/// Explains a missing TCC permission and offers the prompt + the Settings deep link.
struct PermissionBanner: View {
    let title: String
    let explanation: String
    /// Nil hides the request button (e.g. once the user has explicitly denied — only Settings helps then).
    let requestTitle: String?
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let requestTitle {
                    Button(requestTitle, action: onRequest)
                        .buttonStyle(.borderedProminent)
                }
                Button("Open System Settings…", action: onOpenSettings)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
    }
}

extension PermissionBanner {
    static func inputMonitoring(status: InputMonitoringStatus, onRequest: @escaping () -> Void) -> PermissionBanner {
        PermissionBanner(
            title: "Input Monitoring required",
            explanation: status == .denied
                ? "Access was declined. Turn on “Siri Remote Hotkeys” under System Settings → Privacy & Security → Input Monitoring, then reopen this menu. If the remote still shows “not permitted”, quit and relaunch the app."
                : "The remote's button presses arrive as HID input reports, which macOS only hands to apps with Input Monitoring. Remotes are listed without it, but their buttons can't be read.",
            requestTitle: status == .notDetermined ? "Grant Access…" : nil,
            onRequest: onRequest,
            onOpenSettings: InputMonitoringPermission.openSettings)
    }

    static func accessibility(onRequest: @escaping () -> Void) -> PermissionBanner {
        PermissionBanner(
            title: "Accessibility required to send keystrokes",
            explanation: "Bindings exist but macOS only lets trusted apps post keyboard and media-key events. Grant “Siri Remote Hotkeys” under System Settings → Privacy & Security → Accessibility.",
            requestTitle: "Grant Access…",
            onRequest: onRequest,
            onOpenSettings: AccessibilityPermission.openSettings)
    }
}
