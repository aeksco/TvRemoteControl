import AppKit
import RemoteCore
import SwiftUI

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

// MARK: - Tab

/// The bindings editor, sized for the menu-bar panel: the drawn remote is the button selector on the
/// left, the selected button's three gestures stack on the right.
struct BindingsTab: View {
    var monitor: HIDRemoteMonitor
    @Binding var selectedRemoteID: String?
    @Binding var selectedButton: RemoteButton
    @Binding var recording: ButtonGesture?
    var shortcuts: ShortcutsCatalog

    private var remote: RemoteDevice? {
        monitor.remotes.first { $0.id == selectedRemoteID } ?? monitor.remotes.first
    }

    private var buttons: [RemoteButton] {
        remote.flatMap { RemoteProfiles.profile(for: $0.generation)?.buttons } ?? RemoteButton.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            if let remote {
                strip(for: remote)
                Divider()
                HStack(alignment: .top, spacing: 14) {
                    figure
                    detail(for: remote)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(LinearGradient(colors: [PanelTheme.paneTop, PanelTheme.paneBottom],
                                           startPoint: .top, endPoint: .bottom))
                Divider()
                footer(for: remote)
            } else {
                emptyState
            }
        }
        .onAppear {
            // The catalog outlives the tab; only pay for `shortcuts list` when it has nothing yet.
            if shortcuts.names.isEmpty { shortcuts.refresh() }
        }
        .onChange(of: selectedRemoteID) { recording = nil }
        .onChange(of: remote?.heldButtons) { _, held in selectFromRemote(held) }
    }

    /// Pressing a button on the physical remote selects it here — unless a keystroke is being recorded.
    private func selectFromRemote(_ held: ButtonMask?) {
        guard recording == nil, let held, held.buttons.count == 1, let button = held.buttons.first else { return }
        selectedButton = button
    }

    // MARK: Strip

    private func strip(for remote: RemoteDevice) -> some View {
        HStack(spacing: 8) {
            remotePicker(for: remote)
            RemoteCountLabel(monitor: monitor)
            Spacer(minLength: 4)
            boundCount(for: remote)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PanelTheme.strip)
    }

    private func remotePicker(for remote: RemoteDevice) -> some View {
        Menu {
            ForEach(monitor.remotes) { candidate in
                Button(pickerLabel(for: candidate)) { selectedRemoteID = candidate.id }
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
        .help(statusLine(for: remote))
    }

    private func boundCount(for remote: RemoteDevice) -> some View {
        let bound = buttons.filter { button in
            ButtonGesture.allCases.contains { remote.bindings[button, $0] != nil }
        }.count
        return HStack(spacing: 3) {
            Text("\(bound)").foregroundStyle(Color.accentColor)
            Text("of \(buttons.count) bound")
        }
        .font(.system(size: 11))
        .foregroundStyle(PanelTheme.secondary)
        .fixedSize()
    }

    private func pickerLabel(for remote: RemoteDevice) -> String {
        let serial = remote.serialNumber ?? remote.id
        let state = remote.isConnected ? "●" : "○"
        return "\(remote.displayName) · \(serial) \(state)"
    }

    private func statusLine(for remote: RemoteDevice) -> String {
        "\(remote.isConnected ? "Connected" : "Offline") · \(remote.generation.displayName)"
    }

    // MARK: Remote figure

    private var figure: some View {
        VStack(spacing: 8) {
            RemoteFigureView(available: Set(buttons), selected: selectedButton, scale: 0.66) { button in
                selectedButton = button
                recording = nil
            }
            Text("Click a button — or press it on the real remote.")
                .font(.system(size: 10))
                .foregroundStyle(PanelTheme.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 150)
        }
    }

    // MARK: Detail

    private func detail(for remote: RemoteDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(for: remote)
            ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                GestureRowView(
                    gesture: gesture,
                    hint: hint(for: gesture),
                    binding: remote.bindings[selectedButton, gesture],
                    isRecording: recording == gesture,
                    shortcuts: shortcuts,
                    onRecord: { recording = gesture },
                    onCancel: { recording = nil },
                    onSet: { binding in
                        monitor.setBinding(remoteID: remote.id, button: selectedButton, gesture: gesture, binding: binding)
                        recording = nil
                    })
            }
            HoldRow(binding: remote.bindings[selectedButton, .longPress]) { isOn in
                guard let current = remote.bindings[selectedButton, .longPress] else { return }
                monitor.setBinding(remoteID: remote.id, button: selectedButton, gesture: .longPress,
                                   binding: GestureBinding(action: current.action, holdUntilRelease: isOn))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(for remote: RemoteDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selectedButton.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.2)
                Spacer(minLength: 4)
                Text(selectedButton.category)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(RoundedRectangle(cornerRadius: 5).fill(PanelTheme.chip))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(PanelTheme.border))
            }
            Text(description(for: remote))
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                // Reserve the space so the rows below don't jump between one- and three-line blurbs.
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        }
    }

    private func description(for remote: RemoteDevice) -> String {
        var text = selectedButton.blurb
        if selectedButton.nativeMediaKey != nil, !remote.isSeized {
            text += " Exclusive mode is off, so macOS handles it and a binding replaying the same media key is skipped."
        }
        return text
    }

    private func hint(for gesture: ButtonGesture) -> String {
        switch gesture {
        case .press: "on release"
        case .longPress: "after \(monitor.settings.longPressMilliseconds) ms"
        case .doublePress: "within \(monitor.settings.doublePressMilliseconds) ms"
        }
    }

    // MARK: Footer + empty state

    private func footer(for remote: RemoteDevice) -> some View {
        HStack(spacing: 10) {
            Text("Bindings apply system-wide while the remote is connected.")
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            PillButton(title: "Reset") {
                monitor.resetBindings(remoteID: remote.id)
                recording = nil
            }
            .help("Restore this remote's default bindings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No remotes yet", systemImage: "appletvremote.gen4")
                .font(.subheadline.weight(.medium))
            Text("Pair a Siri Remote in System Settings → Bluetooth; it will appear here and keep its bindings by serial number.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(gesture.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.tertiary)
                Spacer(minLength: 4)
                assignMenu
            }
            stateView
        }
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [PanelTheme.cardTop, PanelTheme.cardBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PanelTheme.border))
    }

    @ViewBuilder
    private var stateView: some View {
        if isRecording {
            RecordingPill(
                onRecord: { onSet(GestureBinding(action: .keystroke(combo: $0), holdUntilRelease: keepsHold)) },
                onCancel: onCancel)
        } else if let binding {
            HStack(spacing: 7) {
                Keycap(binding: binding, showsHold: gesture == .longPress)
                ClearButton { onSet(nil) }
                Spacer(minLength: 0)
                Text(binding.action.kindName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(PanelTheme.tertiary)
            }
        } else {
            Text("Not assigned")
                .font(.system(size: 11.5))
                .foregroundStyle(PanelTheme.tertiary)
                .frame(height: 24, alignment: .leading)
        }
    }

    private var assignMenu: some View {
        Menu {
            ActionMenuContent(current: binding, shortcuts: shortcuts, onRecord: onRecord, onSet: onSet)
        } label: {
            HStack(spacing: 5) {
                Text("Assign").font(.system(size: 11.5))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PanelTheme.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(PanelTheme.pill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PanelTheme.border))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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
        HStack(spacing: 5) {
            Image(systemName: binding.action.symbolName)
                .font(.system(size: 10.5))
                .foregroundStyle(PanelTheme.secondary)
            Text(binding.action.displayString)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if showsHold, binding.holdUntilRelease {
                Text("HOLD")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [PanelTheme.keycapTop, PanelTheme.keycapBottom], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PanelTheme.border))
        .shadow(color: Color.black.opacity(0.2), radius: 1, y: 1)
        .help(binding.action.displayString)
    }
}

struct ClearButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovered ? Color.primary : PanelTheme.tertiary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovered ? PanelTheme.pill : Color.clear))
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
                .font(.system(size: 11.5))
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(PanelTheme.pill).brightness(hovered ? 0.05 : 0))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(PanelTheme.border))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// "Hold until release" for the selected button's long-press binding.
struct HoldRow: View {
    let binding: GestureBinding?
    let onToggle: (Bool) -> Void

    private var isAvailable: Bool { binding?.action.isHoldable ?? false }

    private var hint: String {
        isAvailable
            ? "The long-press action stays pressed, auto-repeating, while the button is held."
            : "Assign a keystroke or media key to Long press to enable."
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hold until release")
                    .font(.system(size: 13, weight: .medium))
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("Hold until release", isOn: Binding(get: { binding?.holdUntilRelease ?? false }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!isAvailable)
        }
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PanelTheme.holdCard))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PanelTheme.hairline))
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
        HStack(spacing: 7) {
            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            Text("Press any key combination…")
                .font(.system(size: 11.5))
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(PanelTheme.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor))
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
