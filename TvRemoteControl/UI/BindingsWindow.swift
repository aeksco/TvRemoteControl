import AppKit
import RemoteCore
import SwiftUI

/// The bindings editor lives in a real window (the menu-bar popover is too small for 13 × 3 cells).
/// Managed by hand rather than a SwiftUI `Window` scene so nothing opens at launch in a menu-bar-only app.
@MainActor
final class BindingsWindowController {
    static let shared = BindingsWindowController()

    private var window: NSWindow?

    func show(monitor: HIDRemoteMonitor, remoteID: String? = nil) {
        if window == nil {
            let hosting = NSHostingController(rootView: BindingsEditorView(monitor: monitor, initialRemoteID: remoteID))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Siri Remote Bindings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

struct BindingsEditorView: View {
    var monitor: HIDRemoteMonitor
    let initialRemoteID: String?

    @State private var selectedID: String?
    @State private var recording: BindingKey?
    @State private var shortcuts = ShortcutsCatalog()

    private var remote: RemoteDevice? {
        monitor.remotes.first { $0.id == selectedID } ?? monitor.remotes.first
    }

    private var buttons: [RemoteButton] {
        remote.flatMap { RemoteProfiles.profile(for: $0.generation)?.buttons } ?? RemoteButton.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if monitor.needsAccessibility {
                PermissionBanner(
                    title: "Accessibility required to send keystrokes",
                    explanation: "macOS only lets trusted apps post keyboard and media-key events. Grant “Siri Remote Hotkeys” under System Settings → Privacy & Security → Accessibility. Bindings are saved either way.",
                    requestTitle: "Grant Access…",
                    onRequest: monitor.requestAccessibility,
                    onOpenSettings: AccessibilityPermission.openSettings)
                Divider()
            }
            if let remote {
                ScrollView {
                    grid(for: remote)
                        .padding(16)
                }
                Divider()
                footer(for: remote)
            } else {
                ContentUnavailableView(
                    "No remotes yet",
                    systemImage: "appletvremote.gen4",
                    description: Text("Pair a Siri Remote in System Settings → Bluetooth; it will appear here."))
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            if selectedID == nil {
                selectedID = initialRemoteID ?? monitor.connectedRemotes.first?.id ?? monitor.remotes.first?.id
            }
            monitor.refreshPermission()
            shortcuts.refresh()
        }
        .onChange(of: selectedID) { recording = nil }
    }

    private func pickerLabel(for remote: RemoteDevice) -> String {
        let serial = remote.serialNumber ?? remote.id
        let state = remote.isConnected ? "●" : "○"
        return "\(remote.displayName) · \(serial) \(state)"
    }

    private var footerHint: String {
        recording == nil
            ? "Each cell can send a keystroke or media key, run a Shortcut, or open an app. Long-press keystrokes can Hold until release (auto-repeating until you let go)."
            : "Recording — press the key combination now, or click ✕ to cancel."
    }

    private var header: some View {
        HStack {
            Picker("Remote", selection: $selectedID) {
                ForEach(monitor.remotes) { remote in
                    Text(pickerLabel(for: remote)).tag(Optional(remote.id))
                }
            }
            .frame(maxWidth: 380)
            Spacer()
            if let remote {
                Text(remote.generation.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func grid(for remote: RemoteDevice) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Button").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                    Text(gesture.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Divider().gridCellColumns(ButtonGesture.allCases.count + 1)
            ForEach(buttons, id: \.self) { button in
                GridRow {
                    Label(button.displayName, systemImage: button.symbolName)
                        .frame(width: 130, alignment: .leading)
                    ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                        let key = BindingKey(button: button, gesture: gesture)
                        BindingCell(
                            binding: remote.bindings[button, gesture],
                            gesture: gesture,
                            shortcuts: shortcuts,
                            isRecording: recording == key,
                            onRecord: { recording = key },
                            onCancel: { recording = nil },
                            onSet: { binding in
                                monitor.setBinding(remoteID: remote.id, button: button, gesture: gesture, binding: binding)
                                recording = nil
                            })
                    }
                }
            }
        }
    }

    private func footer(for remote: RemoteDevice) -> some View {
        HStack {
            Text(footerHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset to Defaults") { monitor.resetBindings(remoteID: remote.id) }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One (button, gesture) cell: a pull-down showing the current action, or the recorder while recording.
struct BindingCell: View {
    let binding: GestureBinding?
    let gesture: ButtonGesture
    var shortcuts: ShortcutsCatalog
    let isRecording: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void
    let onSet: (GestureBinding?) -> Void

    /// Recording or picking a media key keeps the cell's hold setting.
    private var keepsHold: Bool { binding?.holdUntilRelease ?? false }

    private var holdToggle: Binding<Bool> {
        Binding(
            get: { binding?.holdUntilRelease ?? false },
            set: { newValue in
                if let binding { onSet(GestureBinding(action: binding.action, holdUntilRelease: newValue)) }
            })
    }

    var body: some View {
        Group {
            if isRecording {
                KeyRecorderField(
                    onRecord: { onSet(GestureBinding(action: .keystroke(combo: $0), holdUntilRelease: keepsHold)) },
                    onCancel: onCancel)
            } else {
                Menu {
                    Button("Record Keystroke…", action: onRecord)
                    Menu("Media Key") {
                        ForEach(MediaKey.allCases, id: \.self) { key in
                            Button(key.displayName) { onSet(GestureBinding(action: .mediaKey(key: key), holdUntilRelease: keepsHold)) }
                        }
                    }
                    shortcutsMenu
                    appsMenu
                    if let binding {
                        Divider()
                        if gesture == .longPress, binding.action.isHoldable {
                            Toggle("Hold until release", isOn: holdToggle)
                        }
                        Button("Remove", role: .destructive) { onSet(nil) }
                    }
                } label: {
                    cellLabel
                }
            }
        }
        .frame(width: 150)
    }

    private var shortcutsMenu: some View {
        Menu("Run Shortcut") {
            if shortcuts.isLoading, shortcuts.names.isEmpty {
                Text("Loading…")
            } else if let error = shortcuts.errorMessage {
                Text(error)
            } else if shortcuts.names.isEmpty {
                Text("No shortcuts found")
            } else {
                ForEach(shortcuts.names, id: \.self) { name in
                    Button(name) { onSet(GestureBinding(action: .runShortcut(name: name))) }
                }
            }
            Divider()
            Button("Refresh List") { shortcuts.refresh() }
        }
    }

    private var appsMenu: some View {
        Menu("Open App") {
            let running = AppChoice.runningApps()
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running) { app in
                        Button(app.name) { onSet(GestureBinding(action: .launchApp(bundleID: app.bundleID, name: app.name))) }
                    }
                }
            }
            Button("Choose Application…") {
                AppChoice.choose { app in
                    guard let app else { return }
                    onSet(GestureBinding(action: .launchApp(bundleID: app.bundleID, name: app.name)))
                }
            }
        }
    }

    private var cellLabel: some View {
        HStack(spacing: 4) {
            if let binding {
                Image(systemName: binding.action.symbolName)
                Text(binding.action.displayString).lineLimit(1)
                if binding.holdUntilRelease {
                    Tag(text: "hold", color: .accentColor)
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Captures the next key-down in this app while visible. Deliberately permissive: every combination is
/// recordable (Esc, ⌘Space, ⌘Tab…) because the goal is to *send* it, not to claim it as a hotkey.
struct KeyRecorderField: View {
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void

    @State private var monitorToken: Any?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "record.circle").foregroundStyle(.red)
            Text("Press keys…").foregroundStyle(.secondary)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.red.opacity(0.6)))
        .onAppear(perform: install)
        .onDisappear(perform: remove)
    }

    private func install() {
        remove()
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let combo = KeyCombo(keyDown: event) {
                // Hop out of the monitor callback before mutating state that tears this view down.
                DispatchQueue.main.async { onRecord(combo) }
            }
            return nil // swallow: the key was recorded, not typed
        }
    }

    private func remove() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
            self.monitorToken = nil
        }
    }
}
