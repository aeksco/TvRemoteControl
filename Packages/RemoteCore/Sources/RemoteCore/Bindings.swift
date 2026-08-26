import Foundation

// MARK: - Key combinations

/// A key combination to synthesize: a macOS virtual key code plus modifier flags.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Apple's canonical display order: ⌃ ⌥ ⇧ ⌘.
        public var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    /// macOS virtual key code (`kVK_*` in Carbon's Events.h), keyboard-layout independent.
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// Human-readable key name captured at record time (layout dependent), e.g. "A", "Space", "←".
    public var keyName: String

    public init(keyCode: UInt16, modifiers: Modifiers = [], keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    public var displayString: String {
        modifiers.symbols + keyName
    }

    /// Keys that real keyboards report with the "fn" flag set (arrows, F-keys, navigation cluster).
    /// Synthetic events should carry it too so apps treat them like hardware presses.
    public var isFunctionKeyGroup: Bool {
        Self.functionKeyGroup.contains(keyCode)
    }

    /// Names for keys that have no printable character. Everything else uses the typed character.
    public static let specialKeyNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 76: "Enter", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 114: "Help", 71: "Clear",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let functionKeyGroup: Set<UInt16> = [
        117, 123, 124, 125, 126, 115, 119, 116, 121, 114,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]
}

extension KeyCombo.Modifiers: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UInt8.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Media keys

/// The special keys on Apple keyboards, delivered to the system as `NX_KEYTYPE_*` system-defined events.
public enum MediaKey: String, Codable, CaseIterable, Sendable {
    case volumeUp, volumeDown, mute, playPause, next, previous, brightnessUp, brightnessDown

    /// `NX_KEYTYPE_*` value from <IOKit/hidsystem/ev_keymap.h>.
    public var nxKeyType: Int {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    public var displayName: String {
        switch self {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play/Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        }
    }
}

// MARK: - Actions

/// What a gesture does. Data only — execution lives in the app behind the `Action` protocol, so adding
/// a case here (Run Shortcut, Launch App, shell script…) is additive.
public enum ActionSpec: Codable, Hashable, Sendable {
    case keystroke(combo: KeyCombo)
    case mediaKey(key: MediaKey)

    public var displayString: String {
        switch self {
        case .keystroke(let combo): combo.displayString
        case .mediaKey(let key): key.displayName
        }
    }

    public var kindName: String {
        switch self {
        case .keystroke: "Keystroke"
        case .mediaKey: "Media key"
        }
    }
}

// MARK: - Bindings

public struct BindingKey: Hashable, Codable, Sendable {
    public let button: RemoteButton
    public let gesture: ButtonGesture

    public init(button: RemoteButton, gesture: ButtonGesture) {
        self.button = button
        self.gesture = gesture
    }
}

/// An action attached to one gesture, plus how to deliver it.
public struct GestureBinding: Hashable, Codable, Sendable {
    public var action: ActionSpec
    /// Long press only: press the action when the long press begins and keep it held — key down with
    /// auto-repeat — until the button is released, instead of tapping it once.
    public var holdUntilRelease: Bool

    public init(action: ActionSpec, holdUntilRelease: Bool = false) {
        self.action = action
        self.holdUntilRelease = holdUntilRelease
    }
}

/// One remote's bindings: (button, gesture) → binding.
public struct BindingSet: Equatable, Sendable {
    public private(set) var entries: [BindingKey: GestureBinding]

    public init(_ entries: [BindingKey: GestureBinding] = [:]) {
        self.entries = entries
    }

    public subscript(button: RemoteButton, gesture: ButtonGesture) -> GestureBinding? {
        get { entries[BindingKey(button: button, gesture: gesture)] }
        set { entries[BindingKey(button: button, gesture: gesture)] = newValue }
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// Buttons with a double-press binding: their single press must wait for the double-press window
    /// (`GestureConfig.deferredPressButtons`) so it does not fire on the way to a double press.
    public var buttonsWithDoublePress: Set<RemoteButton> {
        Set(entries.keys.filter { $0.gesture == .doublePress }.map(\.button))
    }

    /// Starting point for a new remote: each media button replays what macOS would have done natively,
    /// so turning on exclusive mode does not silently kill the volume keys. Holding Volume Up/Down ramps,
    /// like holding the key on a keyboard.
    public static func defaults(for buttons: [RemoteButton]) -> BindingSet {
        var set = BindingSet()
        for button in buttons {
            guard let key = button.nativeMediaKey else { continue }
            set[button, .press] = GestureBinding(action: .mediaKey(key: key))
            if button == .volumeUp || button == .volumeDown {
                set[button, .longPress] = GestureBinding(action: .mediaKey(key: key), holdUntilRelease: true)
            }
        }
        return set
    }
}

extension BindingSet: Codable {
    private struct Entry: Codable {
        let button: RemoteButton
        let gesture: ButtonGesture
        let action: ActionSpec
        /// Optional so files written before the flag existed still decode (missing ⇒ false).
        let holdUntilRelease: Bool?
    }

    public init(from decoder: Decoder) throws {
        let list = try decoder.singleValueContainer().decode([Entry].self)
        self.init(Dictionary(
            list.map {
                (BindingKey(button: $0.button, gesture: $0.gesture),
                 GestureBinding(action: $0.action, holdUntilRelease: $0.holdUntilRelease ?? false))
            },
            uniquingKeysWith: { _, last in last }))
    }

    public func encode(to encoder: Encoder) throws {
        let list = entries
            .map {
                Entry(button: $0.key.button, gesture: $0.key.gesture, action: $0.value.action,
                      holdUntilRelease: $0.value.holdUntilRelease ? true : nil)
            }
            .sorted { ($0.button.rawValue, $0.gesture.rawValue) < ($1.button.rawValue, $1.gesture.rawValue) }
        var container = encoder.singleValueContainer()
        try container.encode(list)
    }
}

public extension RemoteButton {
    /// What macOS does with this button by itself while the remote is *not* seized. Bindings that
    /// replay the same media key are skipped in that state to avoid double-stepping the volume.
    var nativeMediaKey: MediaKey? {
        switch self {
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        case .playPause: .playPause
        default: nil
        }
    }
}
