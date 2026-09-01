import AppKit
import RemoteCore
import SwiftUI

/// The running history, in its own window so the panel can stay small. Opened from the Remotes tab.
@MainActor
enum ActivityLogWindow {
    private static var window: NSWindow?

    static func show(monitor: HIDRemoteMonitor) {
        if window == nil {
            let hosting = NSHostingController(rootView: ActivityLogView(monitor: monitor))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Remote Activity"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 520))
            window.minSize = NSSize(width: 460, height: 320)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        // The panel is closing behind us and this is an accessory app: without activating, the window
        // opens behind whatever is frontmost.
        NSApplication.shared.activate()
    }
}

struct ActivityLogView: View {
    var monitor: HIDRemoteMonitor

    @State private var showsReports = false
    @State private var showsIgnoredDevices = false

    private var entries: [ActivityLog.Entry] {
        showsReports ? monitor.activity.entries : monitor.activity.entries.filter { $0.kind != .report }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Press a button on the remote and it shows up here."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry, remoteName: name(for: entry.remoteID))
                            Divider()
                        }
                    }
                }
            }
            if !monitor.ignoredDevices.isEmpty {
                Divider()
                ignoredSection
            }
        }
        .frame(minWidth: 460, minHeight: 320)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle("Raw reports", isOn: $showsReports)
                .toggleStyle(.checkbox)
                .help("Include every HID input report, including the touch surface's")
            Spacer()
            Button("Clear") { monitor.activity.clear() }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PanelTheme.strip)
    }

    private var ignoredSection: some View {
        DisclosureGroup(isExpanded: $showsIgnoredDevices) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(monitor.ignoredDevices) { device in
                    HStack(spacing: 6) {
                        Text(device.info.product.isEmpty ? "(unnamed)" : device.info.product)
                            .lineLimit(1)
                        Spacer()
                        Text("\(device.info.transport) · PID \(String(format: "0x%04X", device.info.productID)) · \(device.reason)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                }
                Text("If your remote is listed here instead of on the Remotes tab, note its transport and PID — the classifier in RemoteGeneration.swift needs it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.top, 4)
        } label: {
            Text("Other Apple HID devices (\(monitor.ignoredDevices.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Only worth naming the remote when more than one has been seen.
    private func name(for remoteID: String?) -> String? {
        guard monitor.remotes.count > 1, let remoteID else { return nil }
        return monitor.remotes.first { $0.id == remoteID }?.displayName
    }
}

struct EntryRow: View {
    let entry: ActivityLog.Entry
    let remoteName: String?

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.timeFormat.string(from: entry.at))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(entry.kind.label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(color)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.isError ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11, design: entry.kind == .report ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let remoteName {
                Text(remoteName)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .textSelection(.enabled)
    }

    private var color: Color {
        if entry.isError { return .orange }
        switch entry.kind {
        case .gesture: return .accentColor
        case .action: return .green
        case .device: return .purple
        case .report: return .secondary
        }
    }
}
