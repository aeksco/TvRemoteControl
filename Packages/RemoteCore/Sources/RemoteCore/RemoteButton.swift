/// A physical button, independent of generation. Not every generation has every button —
/// `RemoteProfile.buttons` says which exist on a given remote.
public enum RemoteButton: String, Codable, CaseIterable, Sendable, Hashable {
    case power
    case back          // gen 2/3 "‹"; on gen 1 this is Menu
    case tv            // TV / Control Center (gen 2/3), Home (gen 1)
    case select        // clickpad centre click (gen 2/3), touch-surface click (gen 1)
    case up, down, left, right
    case playPause
    case mute
    case volumeUp
    case volumeDown
    case siri

    public var displayName: String {
        switch self {
        case .power: "Power"
        case .back: "Back"
        case .tv: "TV"
        case .select: "Select"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .playPause: "Play/Pause"
        case .mute: "Mute"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .siri: "Siri"
        }
    }

    /// Bit used for this button inside `ButtonMask`. App-internal — unrelated to any HID bit position.
    public var mask: ButtonMask {
        ButtonMask(rawValue: 1 << UInt16(Self.bitIndex[self]!))
    }

    private static let bitIndex: [RemoteButton: Int] = Dictionary(
        uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })
}

/// Set of buttons currently held. One bit per `RemoteButton`, so chords are representable.
public struct ButtonMask: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public init(_ buttons: some Sequence<RemoteButton>) {
        self.init(rawValue: buttons.reduce(0) { $0 | $1.mask.rawValue })
    }

    public var buttons: [RemoteButton] {
        RemoteButton.allCases.filter { contains($0.mask) }
    }

    public func contains(_ button: RemoteButton) -> Bool {
        contains(button.mask)
    }
}

// Static members so masks can be written as literals: `[.volumeUp, .select]`.
public extension ButtonMask {
    static let power = RemoteButton.power.mask
    static let back = RemoteButton.back.mask
    static let tv = RemoteButton.tv.mask
    static let select = RemoteButton.select.mask
    static let up = RemoteButton.up.mask
    static let down = RemoteButton.down.mask
    static let left = RemoteButton.left.mask
    static let right = RemoteButton.right.mask
    static let playPause = RemoteButton.playPause.mask
    static let mute = RemoteButton.mute.mask
    static let volumeUp = RemoteButton.volumeUp.mask
    static let volumeDown = RemoteButton.volumeDown.mask
    static let siri = RemoteButton.siri.mask
}
