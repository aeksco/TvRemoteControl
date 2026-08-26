/// Hardware generation of a Siri Remote. Selects the `RemoteProfile` (report layout).
public enum RemoteGeneration: String, Codable, CaseIterable, Sendable {
    case gen1      // A1513 (2015), A1962 (2017): touch surface, Menu/Home/Play-Pause/Siri/Vol±, touch click
    case gen2      // A2540 (2021): clickpad, Lightning
    case gen3      // A2854 (2022): clickpad, USB-C — same buttons and report layout as gen2
    case unknown   // Apple Bluetooth HID device we have not classified yet

    public var displayName: String {
        switch self {
        case .gen1: "1st generation"
        case .gen2: "2nd generation"
        case .gen3: "3rd generation"
        case .unknown: "Generation unknown"
        }
    }

    public var modelNumbers: String {
        switch self {
        case .gen1: "A1513 / A1962"
        case .gen2: "A2540"
        case .gen3: "A2854"
        case .unknown: "—"
        }
    }

    public var hasClickpad: Bool {
        self == .gen2 || self == .gen3
    }
}
