import AppKit
import CoreGraphics
import Foundation
import RemoteCore

enum ActionError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted: "Accessibility permission is required to send keystrokes"
        case .eventCreationFailed: "Couldn't create the synthetic event"
        }
    }
}

/// Something a gesture can do. Each `ActionSpec` case maps to one implementation.
protocol Action {
    var displayString: String { get }
    /// Tap: the whole action at once.
    func perform() throws
}

/// Actions with a down/up shape that can be held for the duration of a long press. `HoldController`
/// drives the repeats and guarantees `keyUp()` eventually runs.
protocol HoldableAction: Action {
    func keyDown(isRepeat: Bool) throws
    func keyUp() throws
}

extension HoldableAction {
    func perform() throws {
        try keyDown(isRepeat: false)
        try keyUp()
    }
}

extension ActionSpec {
    func makeAction() -> any Action {
        switch self {
        case .keystroke(let combo): KeystrokeAction(combo: combo)
        case .mediaKey(let key): MediaKeyAction(key: key)
        }
    }

    var symbolName: String {
        switch self {
        case .keystroke: "keyboard"
        case .mediaKey(let key): key.symbolName
        }
    }
}

extension MediaKey {
    var symbolName: String {
        switch self {
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .next: "forward.end"
        case .previous: "backward.end"
        case .brightnessUp: "sun.max"
        case .brightnessDown: "sun.min"
        }
    }
}

/// Posts key down / key up events with modifier flags to the HID event tap, as if typed.
struct KeystrokeAction: HoldableAction {
    let combo: KeyCombo

    var displayString: String { combo.displayString }

    func keyDown(isRepeat: Bool) throws {
        let event = try makeEvent(keyDown: true)
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    func keyUp() throws {
        try makeEvent(keyDown: false).post(tap: .cghidEventTap)
    }

    private func makeEvent(keyDown: Bool) throws -> CGEvent {
        guard AccessibilityPermission.isTrusted() else { throw ActionError.accessibilityNotGranted }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(combo.keyCode), keyDown: keyDown) else {
            throw ActionError.eventCreationFailed
        }
        var flags = combo.modifiers.cgEventFlags
        if combo.isFunctionKeyGroup { flags.insert(.maskSecondaryFn) }
        event.flags = flags
        return event
    }
}

/// Replays an Apple media key (volume, play/pause…) as the system-defined event a keyboard would send.
struct MediaKeyAction: HoldableAction {
    let key: MediaKey

    var displayString: String { key.displayName }

    func keyDown(isRepeat: Bool) throws {
        try post(down: true, isRepeat: isRepeat)
    }

    func keyUp() throws {
        try post(down: false, isRepeat: false)
    }

    private func post(down: Bool, isRepeat: Bool) throws {
        guard AccessibilityPermission.isTrusted() else { throw ActionError.accessibilityNotGranted }
        // Layout of NX_SUBTYPE_AUX_CONTROL_BUTTONS events: key type in the high word of data1, key state
        // (0xA down / 0xB up) in the next byte, repeat flag in the low byte. Modifier flags mirror the state.
        let state = down ? 0xA : 0xB
        let data1 = (key.nxKeyType << 16) | (state << 8) | (isRepeat ? 1 : 0)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cgEvent = event.cgEvent else {
            throw ActionError.eventCreationFailed
        }
        cgEvent.post(tap: .cghidEventTap)
    }
}

extension KeyCombo.Modifiers {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}

extension KeyCombo {
    /// Build a combo from a key-down event captured by the recorder.
    init?(keyDown event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Modifiers()
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let typed = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let name = KeyCombo.specialKeyNames[event.keyCode]
            ?? (typed.isEmpty || typed.unicodeScalars.contains { !$0.properties.isGraphemeBase } ? "Key \(event.keyCode)" : typed)
        self.init(keyCode: event.keyCode, modifiers: modifiers, keyName: name)
    }
}
