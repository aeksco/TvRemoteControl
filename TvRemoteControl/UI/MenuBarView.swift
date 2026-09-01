import AppKit
import RemoteCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case remotes, bindings

    var id: Self { self }

    var title: String {
        switch self {
        case .remotes: "Remotes"
        case .bindings: "Bindings"
        }
    }
}

/// The whole app lives in this panel. `.menuBarExtraStyle(.window)` hosts arbitrary SwiftUI — the only
/// real constraint is width — so the bindings editor is a tab here rather than a separate window.
/// Selection state lives at this level so switching tabs (or reopening the panel) keeps its place.
struct MenuBarView: View {
    var monitor: HIDRemoteMonitor

    @State private var tab: PanelTab = .remotes
    @State private var selectedRemoteID: String?
    @State private var selectedButton: RemoteButton = .select
    @State private var recording: ButtonGesture?
    @State private var shortcuts = ShortcutsCatalog()

    static let width: CGFloat = 620

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

            switch tab {
            case .remotes:
                RemotesTab(monitor: monitor, selectedRemoteID: $selectedRemoteID)
            case .bindings:
                BindingsTab(
                    monitor: monitor,
                    selectedRemoteID: $selectedRemoteID,
                    selectedButton: $selectedButton,
                    recording: $recording,
                    shortcuts: shortcuts)
            }

            Divider()
            footer
        }
        .frame(width: Self.width)
        .onAppear {
            monitor.refreshPermission()
            if selectedRemoteID == nil {
                selectedRemoteID = monitor.connectedRemotes.first?.id ?? monitor.remotes.first?.id
            }
        }
        // A half-finished recording must not survive leaving the tab.
        .onChange(of: tab) { recording = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Siri Remote Hotkeys")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Section", selection: $tab) {
                ForEach(PanelTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            Button("Bluetooth Settings…") { Self.openBluetoothSettings() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    static func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}
