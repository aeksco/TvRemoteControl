import AppKit
import SwiftUI

struct MenuBarView: View {
    var monitor: HIDRemoteMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if monitor.inputMonitoring != .granted {
                PermissionBanner.inputMonitoring(status: monitor.inputMonitoring, onRequest: monitor.requestPermission)
                Divider()
            }
            if monitor.needsAccessibility {
                PermissionBanner.accessibility(onRequest: monitor.requestAccessibility)
                Divider()
            }

            if monitor.remotes.isEmpty {
                emptyState
            } else {
                remotesList
            }

            Divider()
            SettingsSection(settings: monitor.settings, seizedDeviceCount: monitor.seizedDeviceCount)

            if !monitor.ignoredDevices.isEmpty {
                Divider()
                ignoredSection
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear { monitor.refreshPermission() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Siri Remote Hotkeys").font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusLine: String {
        let connected = monitor.connectedRemotes.count
        switch (connected, monitor.remotes.count) {
        case (0, 0): return "No remotes seen yet"
        case (0, let known): return "\(known) known remote\(known == 1 ? "" : "s"), none connected"
        case (let c, _): return "\(c) remote\(c == 1 ? "" : "s") connected"
        }
    }

    private var remotesList: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                ForEach(monitor.remotes) { remote in
                    RemoteRow(remote: remote, now: context.date)
                }
            }
            .padding(6)
        }
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
            Button("Open Bluetooth Settings…") { openBluetoothSettings() }
                .controlSize(.small)
        }
        .padding(12)
    }

    private var ignoredSection: some View {
        DisclosureGroup {
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
                Text("If your remote is listed here instead of above, note its transport and PID — the classifier in RemoteGeneration.swift needs it.")
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

    private var footer: some View {
        HStack {
            Button("Bindings…") { BindingsWindowController.shared.show(monitor: monitor) }
                .keyboardShortcut("b")
            Button("Bluetooth Settings…") { openBluetoothSettings() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}
