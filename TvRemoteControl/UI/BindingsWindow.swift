import AppKit
import RemoteCore
import SwiftUI

// MARK: - Window

/// The bindings editor lives in a real window (the menu-bar popover is far too small). Managed by hand
/// rather than a SwiftUI `Window` scene so nothing opens at launch in a menu-bar-only app.
@MainActor
final class BindingsWindowController {
    static let shared = BindingsWindowController()

    private var window: NSWindow?

    func show(monitor: HIDRemoteMonitor, remoteID: String? = nil) {
        if window == nil {
            let hosting = NSHostingController(rootView: BindingsEditorView(monitor: monitor, initialRemoteID: remoteID))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Remote Bindings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1060, height: 720))
            window.minSize = NSSize(width: 960, height: 620)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

// MARK: - Theme

/// Dark values are lifted from the Claude Design mockup ("Remote Bindings"); light values keep the same
/// structure so the window follows the system appearance.
enum BindingsTheme {
    static let window = Color.adaptive(light: 0xF3F3F5, dark: 0x1B1B1D)
    static let toolbar = Color.adaptive(light: 0xEAEAED, dark: 0x212124)
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

// MARK: - Button copy

extension RemoteButton {
    var category: String {
        switch self {
        case .power, .siri: "System"
        case .back, .tv: "Navigation"
        case .select, .up, .down, .left, .right: "Clickpad"
        case .playPause, .mute, .volumeUp, .volumeDown: "Media"
        }
    }

    var blurb: String {
        switch self {
        case .power: "Top-right button. Sleeps and wakes an Apple TV natively; on the Mac it is just a button."
        case .back: "The ‹ button. Esc is the classic mapping."
        case .tv: "The TV / Control Center button."
        case .select: "Clickpad centre press."
        case .up: "Clickpad directional press, top edge."
        case .down: "Clickpad directional press, bottom edge."
        case .left: "Clickpad directional press, left edge."
        case .right: "Clickpad directional press, right edge."
        case .playPause: "Toggles playback in the focused media app."
        case .mute: "Mutes and unmutes system output."
        case .volumeUp: "Volume rocker, upper half."
        case .volumeDown: "Volume rocker, lower half."
        case .siri: "Side button. Holds for voice input on an Apple TV; here it is a plain button."
        }
    }
}

// MARK: - Editor

struct BindingsEditorView: View {
    var monitor: HIDRemoteMonitor
    let initialRemoteID: String?

    @State private var selectedID: String?
    @State private var selectedButton: RemoteButton = .select
    @State private var recording: ButtonGesture?
    @State private var shortcuts = ShortcutsCatalog()

    private var remote: RemoteDevice? {
        monitor.remotes.first { $0.id == selectedID } ?? monitor.remotes.first
    }

    private var buttons: [RemoteButton] {
        remote.flatMap { RemoteProfiles.profile(for: $0.generation)?.buttons } ?? RemoteButton.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(BindingsTheme.hairline).frame(height: 1)
            if monitor.needsAccessibility {
                PermissionBanner.accessibility(onRequest: monitor.requestAccessibility)
                Rectangle().fill(BindingsTheme.hairline).frame(height: 1)
            }
            if let remote {
                HStack(spacing: 0) {
                    remotePane(remote)
                    Rectangle().fill(BindingsTheme.hairline).frame(width: 1)
                    ButtonDetailPane(
                        monitor: monitor, remote: remote, button: selectedButton,
                        recording: $recording, shortcuts: shortcuts)
                }
            } else {
                ContentUnavailableView(
                    "No remotes yet",
                    systemImage: "appletvremote.gen4",
                    description: Text("Pair a Siri Remote in System Settings → Bluetooth; it will appear here."))
            }
        }
        .background(BindingsTheme.window)
        .frame(minWidth: 960, minHeight: 620)
        .onAppear {
            if selectedID == nil {
                selectedID = initialRemoteID ?? monitor.connectedRemotes.first?.id ?? monitor.remotes.first?.id
            }
            monitor.refreshPermission()
            shortcuts.refresh()
        }
        .onChange(of: selectedID) { recording = nil }
        .onChange(of: remote?.heldButtons) { _, held in
            selectFromRemote(held)
        }
    }

    /// Pressing a button on the physical remote selects it here — unless a keystroke is being recorded.
    private func selectFromRemote(_ held: ButtonMask?) {
        guard recording == nil, let held, held.buttons.count == 1, let button = held.buttons.first else { return }
        selectedButton = button
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            remotePicker
            if let remote {
                Text(statusLine(for: remote))
                    .font(.system(size: 12))
                    .foregroundStyle(BindingsTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let remote {
                boundCount(for: remote)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 60)
        .background(BindingsTheme.toolbar)
    }

    private var remotePicker: some View {
        Menu {
            ForEach(monitor.remotes) { candidate in
                Button(pickerLabel(for: candidate)) { selectedID = candidate.id }
            }
        } label: {
            pickerPill
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var pickerPill: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(remote?.isConnected == true ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
                .shadow(color: (remote?.isConnected == true ? Color.green : .clear).opacity(0.7), radius: 4)
            Text(remote?.displayName ?? "No remote")
                .font(.system(size: 13))
            Text(remote?.serialNumber ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(BindingsTheme.secondary)
            Text("▾")
                .font(.system(size: 11))
                .foregroundStyle(BindingsTheme.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(BindingsTheme.pill))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BindingsTheme.border))
    }

    private func boundCount(for remote: RemoteDevice) -> some View {
        let bound = buttons.filter { button in
            ButtonGesture.allCases.contains { remote.bindings[button, $0] != nil }
        }.count
        return HStack(spacing: 4) {
            Text("\(bound)").foregroundStyle(Color.accentColor)
            Text("of \(buttons.count) buttons bound")
        }
        .font(.system(size: 12.5))
        .foregroundStyle(BindingsTheme.secondary)
    }

    private func pickerLabel(for remote: RemoteDevice) -> String {
        let serial = remote.serialNumber ?? remote.id
        let state = remote.isConnected ? "●" : "○"
        return "\(remote.displayName) · \(serial) \(state)"
    }

    private func statusLine(for remote: RemoteDevice) -> String {
        let state = remote.isConnected ? "Connected" : "Offline"
        return "\(state) · \(remote.generation.displayName)"
    }

    // MARK: Remote pane

    private func remotePane(_ remote: RemoteDevice) -> some View {
        VStack(spacing: 22) {
            RemoteFigureView(available: Set(buttons), selected: selectedButton) { button in
                selectedButton = button
                recording = nil
            }
            Text("Select a button on the remote — or press it on the real one — to edit its bindings.")
                .font(.system(size: 12))
                .foregroundStyle(BindingsTheme.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 230)
            Spacer(minLength: 0)
        }
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [BindingsTheme.paneTop, BindingsTheme.paneBottom], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Detail pane

struct ButtonDetailPane: View {
    var monitor: HIDRemoteMonitor
    let remote: RemoteDevice
    let button: RemoteButton
    @Binding var recording: ButtonGesture?
    var shortcuts: ShortcutsCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(spacing: 12) {
                        ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                            row(for: gesture)
                        }
                    }
                    .padding(.top, 22)
                    HoldCard(binding: remote.bindings[button, .longPress]) { isOn in
                        guard let current = remote.bindings[button, .longPress] else { return }
                        monitor.setBinding(remoteID: remote.id, button: button, gesture: .longPress,
                                           binding: GestureBinding(action: current.action, holdUntilRelease: isOn))
                    }
                    .padding(.top, 18)
                }
                .padding(.top, 30)
                .padding(.horizontal, 32)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text("SELECTED BUTTON")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 7)
                Text(button.displayName)
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.4)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(BindingsTheme.secondary)
                    .padding(.top, 6)
                    .frame(maxWidth: 440, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(button.category)
                .font(.system(size: 12))
                .foregroundStyle(BindingsTheme.secondary)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(BindingsTheme.chip))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(BindingsTheme.border))
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) { Rectangle().fill(BindingsTheme.hairline).frame(height: 1) }
    }

    private var description: String {
        var text = button.blurb
        if button.nativeMediaKey != nil, !remote.isSeized {
            text += " While exclusive mode is off, macOS handles this button itself and a binding that replays the same media key is skipped."
        }
        return text
    }

    private func row(for gesture: ButtonGesture) -> some View {
        GestureRowView(
            gesture: gesture,
            hint: hint(for: gesture),
            binding: remote.bindings[button, gesture],
            isRecording: recording == gesture,
            shortcuts: shortcuts,
            onRecord: { recording = gesture },
            onCancel: { recording = nil },
            onSet: { binding in
                monitor.setBinding(remoteID: remote.id, button: button, gesture: gesture, binding: binding)
                recording = nil
            })
    }

    private func hint(for gesture: ButtonGesture) -> String {
        switch gesture {
        case .press: "Fires on release of a single click."
        case .longPress: "Fires after holding for \(monitor.settings.longPressMilliseconds) ms."
        case .doublePress: "Two clicks within \(monitor.settings.doublePressMilliseconds) ms."
        }
    }

    private var footer: some View {
        HStack(spacing: 20) {
            Text("Bindings apply system-wide while the remote is connected. Keystrokes go to whichever app is focused.")
                .font(.system(size: 12))
                .foregroundStyle(BindingsTheme.tertiary)
                .frame(maxWidth: 440, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            PillButton(title: "Reset to Defaults") {
                monitor.resetBindings(remoteID: remote.id)
                recording = nil
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Rectangle().fill(BindingsTheme.hairline).frame(height: 1).padding(.horizontal, 32) }
    }
}

// MARK: - Gesture row

struct GestureRowView: View {
    let gesture: ButtonGesture
    let hint: String
    let binding: GestureBinding?
    let isRecording: Bool
    var shortcuts: ShortcutsCatalog
    let onRecord: () -> Void
    let onCancel: () -> Void
    let onSet: (GestureBinding?) -> Void

    private var keepsHold: Bool { binding?.holdUntilRelease ?? false }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gesture.displayName)
                    .font(.system(size: 14.5, weight: .medium))
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(BindingsTheme.secondary)
            }
            .frame(minWidth: 170, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                stateView
                assignMenu
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [BindingsTheme.cardTop, BindingsTheme.cardBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(BindingsTheme.border))
    }

    @ViewBuilder
    private var stateView: some View {
        if isRecording {
            RecordingPill(
                onRecord: { onSet(GestureBinding(action: .keystroke(combo: $0), holdUntilRelease: keepsHold)) },
                onCancel: onCancel)
        } else if let binding {
            HStack(spacing: 9) {
                Text(binding.action.kindName.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(BindingsTheme.tertiary)
                Keycap(binding: binding, showsHold: gesture == .longPress)
                ClearButton { onSet(nil) }
            }
        } else {
            Text("Not assigned")
                .font(.system(size: 13))
                .foregroundStyle(BindingsTheme.tertiary)
        }
    }

    private var assignMenu: some View {
        Menu {
            ActionMenuContent(current: binding, shortcuts: shortcuts, onRecord: onRecord, onSet: onSet)
        } label: {
            HStack(spacing: 7) {
                Text("Assign").font(.system(size: 12.5))
                Text("▾").font(.system(size: 10)).foregroundStyle(BindingsTheme.tertiary)
            }
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(BindingsTheme.pill))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BindingsTheme.border))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The items of the Assign menu; the kind-specific submenus live here so they can be reused.
struct ActionMenuContent: View {
    let current: GestureBinding?
    var shortcuts: ShortcutsCatalog
    let onRecord: () -> Void
    let onSet: (GestureBinding?) -> Void

    private var keepsHold: Bool { current?.holdUntilRelease ?? false }

    var body: some View {
        Button("Record Keystroke…", action: onRecord)
        Menu("Media Key") {
            ForEach(MediaKey.allCases, id: \.self) { key in
                Button(key.displayName) { onSet(GestureBinding(action: .mediaKey(key: key), holdUntilRelease: keepsHold)) }
            }
        }
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
        if current != nil {
            Divider()
            Button("Remove Binding", role: .destructive) { onSet(nil) }
        }
    }
}

// MARK: - Small pieces

/// The assigned action rendered as a keycap.
struct Keycap: View {
    let binding: GestureBinding
    let showsHold: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: binding.action.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(BindingsTheme.secondary)
            Text(binding.action.displayString)
                .font(.system(size: 13.5, weight: .medium))
                .lineLimit(1)
            if showsHold, binding.holdUntilRelease {
                Text("HOLD")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [BindingsTheme.keycapTop, BindingsTheme.keycapBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BindingsTheme.border))
        .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
    }
}

struct ClearButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovered ? Color.primary : BindingsTheme.tertiary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovered ? BindingsTheme.pill : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Remove binding")
    }
}

struct PillButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .padding(.horizontal, 15)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(BindingsTheme.pill).brightness(hovered ? 0.05 : 0))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BindingsTheme.border))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// "Hold until release" for the selected button's long-press binding.
struct HoldCard: View {
    let binding: GestureBinding?
    let onToggle: (Bool) -> Void

    private var isAvailable: Bool { binding?.action.isHoldable ?? false }

    private var hint: String {
        isAvailable
            ? "The long-press keystroke or media key stays pressed, auto-repeating, while the button is held."
            : "Assign a keystroke or media key to Long press to enable."
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hold until release")
                    .font(.system(size: 13.5, weight: .medium))
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(BindingsTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("Hold until release", isOn: Binding(get: { binding?.holdUntilRelease ?? false }, set: onToggle))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isAvailable)
        }
        .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(BindingsTheme.holdCard))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(BindingsTheme.hairline))
    }
}

/// Captures the next key-down in this app while visible. Deliberately permissive: every combination is
/// recordable (Esc, ⌘Space, ⌘Tab…) because the goal is to *send* it, not to claim it as a hotkey.
struct RecordingPill: View {
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void

    @State private var monitorToken: Any?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
            Text("Press any key combination…")
                .font(.system(size: 13))
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BindingsTheme.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor))
        .opacity(pulse ? 0.5 : 1)
        .onAppear {
            install()
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
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
