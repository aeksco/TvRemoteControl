import AppKit
import RemoteCore
import SwiftUI

/// The panel's default tab, laid out like the Bindings tab: the drawn remote on the left — where a
/// press lights the key up as it happens — and the selected remote's state on the right. The running
/// history moved to the Activity Log window; this tab shows only what is true right now.
struct RemotesTab: View {
    var monitor: HIDRemoteMonitor
    @Binding var selectedRemoteID: String?

    /// The last button that fired a gesture, held briefly so a quick tap is still visible.
    @State private var flash: RemoteButton?

    private var remote: RemoteDevice? {
        monitor.remotes.first { $0.id == selectedRemoteID } ?? monitor.remotes.first
    }

    private var buttons: [RemoteButton] {
        remote.flatMap { RemoteProfiles.profile(for: $0.generation)?.buttons } ?? RemoteButton.allCases
    }

    private var litButtons: Set<RemoteButton> {
        var lit = Set(remote?.heldButtons.buttons ?? [])
        if let flash { lit.insert(flash) }
        return lit
    }

    var body: some View {
        VStack(spacing: 0) {
            if let remote {
                strip(for: remote)
                Divider()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .top, spacing: 14) {
                        figure(for: remote)
                        detail(for: remote, now: context.date)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [PanelTheme.paneTop, PanelTheme.paneBottom],
                                               startPoint: .top, endPoint: .bottom))
                }
                Divider()
                footer(for: remote)
            } else {
                emptyState
            }
        }
        .onChange(of: remote?.eventCount) {
            guard let button = remote?.recentEvents.first?.button else { return }
            flash = button
            Task {
                try? await Task.sleep(for: .milliseconds(260))
                if flash == button { flash = nil }
            }
        }
    }

    // MARK: Strip

    private func strip(for remote: RemoteDevice) -> some View {
        HStack(spacing: 8) {
            RemotePickerPill(remotes: monitor.remotes, selection: $selectedRemoteID, remote: remote)
            RemoteCountLabel(monitor: monitor)
            Spacer(minLength: 4)
            if remote.isSeized {
                Tag(text: "Exclusive", color: .orange)
            }
            if remote.isConnected, let battery = remote.batteryPercent {
                Label("\(battery)%", systemImage: batterySymbol(for: battery))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PanelTheme.strip)
    }

    // MARK: Remote figure

    private func figure(for remote: RemoteDevice) -> some View {
        VStack(spacing: 8) {
            RemoteFigureView(available: Set(buttons), highlighted: litButtons, scale: 0.66)
            Text(remote.isConnected ? "Presses light up here." : "Reconnect the remote to see presses.")
                .font(.system(size: 10))
                .foregroundStyle(PanelTheme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 150)
        }
    }

    // MARK: Detail

    private func detail(for remote: RemoteDevice, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(for: remote)
            LiveCard(remote: remote, now: now)
            PanelCard {
                InfoRow(label: "State", value: stateText(for: remote, now: now))
                InfoRow(label: "Mode", value: remote.isSeized ? "Exclusive — macOS ignores the remote" : "Shared with macOS")
                InfoRow(label: "Activity", value: "\(remote.inputCount) reports · \(remote.eventCount) gestures")
                InfoRow(label: "Bindings", value: "\(remote.bindings.count) assigned")
            }
            PanelCard {
                InfoRow(label: "Serial", value: remote.serialNumber ?? "—", isMonospaced: true)
                InfoRow(label: "Product", value: "PID \(remote.productIDHex) · \(remote.transport)", isMonospaced: true)
            }
            warnings(for: remote)
            SettingsCard(settings: monitor.settings, seizedDeviceCount: monitor.seizedDeviceCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(for remote: RemoteDevice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(remote.displayName)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.2)
            Spacer(minLength: 4)
            Text(remote.generation.displayName)
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.secondary)
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(RoundedRectangle(cornerRadius: 5).fill(PanelTheme.chip))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PanelTheme.border))
        }
    }

    @ViewBuilder
    private func warnings(for remote: RemoteDevice) -> some View {
        if let error = remote.openError {
            WarningCard(text: "Can't read input — \(error)")
        } else if remote.isConnected, !remote.hasProfile {
            WarningCard(text: "No verified button layout for this generation yet — reports arrive, but no gestures are decoded. The Activity Log shows the raw bytes.")
        } else if !monitor.settings.isEnabled {
            WarningCard(text: "Decoding is off in Settings, so buttons are left to macOS.")
        }
    }

    private func stateText(for remote: RemoteDevice, now: Date) -> String {
        if remote.isConnected {
            if let last = remote.lastInputAt {
                return "Connected · last input \(RelativeTime.string(from: last, now: now))"
            }
            return "Connected · no input yet"
        }
        return "Offline · last seen \(RelativeTime.string(from: remote.lastSeenAt, now: now))"
    }

    private func batterySymbol(for percent: Int) -> String {
        switch percent {
        case ..<10: "battery.0percent"
        case ..<35: "battery.25percent"
        case ..<60: "battery.50percent"
        case ..<85: "battery.75percent"
        default: "battery.100percent"
        }
    }

    // MARK: Footer + empty state

    private func footer(for remote: RemoteDevice) -> some View {
        HStack(spacing: 10) {
            Text(monitor.ignoredDevices.isEmpty
                 ? "Every gesture, action and raw report is kept in the log."
                 : "The log also lists the \(monitor.ignoredDevices.count) other Apple HID devices seen.")
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            PillButton(title: "Activity Log…") { ActivityLogWindow.show(monitor: monitor) }
                .help("Open the running log of gestures, actions and raw HID reports in its own window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No Siri Remote found", systemImage: "appletvremote.gen4")
                .font(.subheadline.weight(.medium))
            Text("Pair the remote in System Settings → Bluetooth. It bonds to one host at a time, so unpair it from the Apple TV first. It may show up as a MAC address before its serial number appears.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pairing mode — 1st gen: hold Menu + Volume Up. 2nd/3rd gen: hold Back + Volume Up for ~5 s.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Bluetooth Settings…") { MenuBarView.openBluetoothSettings() }
                Button("Activity Log…") { ActivityLogWindow.show(monitor: monitor) }
            }
            .controlSize(.small)
        }
        .padding(12)
    }
}

// MARK: - Shared pieces

/// The remote chooser, identical in both tabs: connection dot, name, serial, chevron.
struct RemotePickerPill: View {
    let remotes: [RemoteDevice]
    @Binding var selection: String?
    let remote: RemoteDevice

    var body: some View {
        Menu {
            ForEach(remotes) { candidate in
                Button(label(for: candidate)) { selection = candidate.id }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(remote.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(remote.displayName)
                    .font(.system(size: 12))
                Text(remote.serialNumber ?? remote.productIDHex)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PanelTheme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PanelTheme.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(PanelTheme.pill))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(PanelTheme.border))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(remote.isConnected ? "Connected" : "Offline") · \(remote.generation.displayName)")
    }

    private func label(for remote: RemoteDevice) -> String {
        "\(remote.displayName) · \(remote.serialNumber ?? remote.id) \(remote.isConnected ? "●" : "○")"
    }
}

/// "1 remote connected" — the panel's status line, in the strip beside the picker so both tabs carry it.
struct RemoteCountLabel: View {
    var monitor: HIDRemoteMonitor

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(PanelTheme.tertiary)
            .lineLimit(1)
    }

    private var text: String {
        let connected = monitor.connectedRemotes.count
        switch (connected, monitor.remotes.count) {
        case (0, 0): return "No remotes seen yet"
        case (0, let known): return "\(known) known remote\(known == 1 ? "" : "s"), none connected"
        case (let c, _): return "\(c) remote\(c == 1 ? "" : "s") connected"
        }
    }
}

/// The most recent gesture and what it did — the tab's answer to "did that press register?".
struct LiveCard: View {
    let remote: RemoteDevice
    let now: Date

    var body: some View {
        PanelCard {
            if let event = remote.recentEvents.first {
                HStack(spacing: 7) {
                    Image(systemName: event.button.symbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text("\(event.button.displayName) · \(event.gesture.displayName)")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 4)
                    if let at = remote.lastInputAt {
                        Text(RelativeTime.string(from: at, now: now))
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelTheme.tertiary)
                    }
                }
                if let feedback = remote.lastAction {
                    Label(feedbackText(feedback), systemImage: feedback.error == nil ? "arrow.turn.down.right" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(feedback.error == nil ? AnyShapeStyle(PanelTheme.secondary) : AnyShapeStyle(Color.orange))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nothing bound to it — assign an action in the Bindings tab.")
                        .font(.system(size: 11))
                        .foregroundStyle(PanelTheme.secondary)
                }
            } else {
                Text(remote.isConnected ? "Waiting for input" : "No input recorded")
                    .font(.system(size: 13, weight: .medium))
                Text(remote.isConnected
                     ? "Press any button on the remote — it lights up on the left."
                     : "The remote is offline; its bindings are kept.")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feedbackText(_ feedback: ActionFeedback) -> String {
        var text = feedback.summary
        if let error = feedback.error { text += " — \(error)" }
        return text
    }
}

/// A card in the panel's right column — same shape as the gesture cards in the Bindings tab.
struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [PanelTheme.cardTop, PanelTheme.cardBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PanelTheme.border))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.tertiary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, design: isMonospaced ? .monospaced : .default))
                .foregroundStyle(PanelTheme.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct WarningCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.orange.opacity(0.35)))
    }
}

enum RelativeTime {
    static func string(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded(.down))
        switch seconds {
        case ..<1: return "just now"
        case ..<60: return "\(seconds) s ago"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86400: return "\(seconds / 3600) h ago"
        default: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
