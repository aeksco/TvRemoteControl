/// Report layout for one hardware generation. Implementations must be pure.
public protocol RemoteProfile: Sendable {
    var generation: RemoteGeneration { get }
    /// Buttons that physically exist on this remote, in a sensible display order.
    var buttons: [RemoteButton] { get }
    /// HID usage page / usage of the sub-device that carries the button report. The remote publishes
    /// several `IOHIDDevice`s; only reports from this one are decoded.
    var buttonUsagePage: Int { get }
    var buttonUsage: Int { get }
    /// Decode one input report into the set of held buttons. `bytes` is the raw report as delivered by
    /// IOKit (report ID byte first). Returns nil for reports that are not the button report.
    func decode(reportID: UInt32, bytes: [UInt8]) -> ButtonMask?
}

/// Clickpad Siri Remote — 2nd gen (A2540) and 3rd gen (A2854) share this layout.
///
/// Captured from remote C08N44382330 (PID 0x0315) on 2026-08-25, see BUTTONS.md:
/// Consumer Control sub-device (usage 0x0C/0x01), input report ID 0xFB, three bytes `fb <b1> <b2>`,
/// thirteen 1-bit fields LSB-first in report-descriptor order, then 3 bits of padding.
public struct ClickpadRemoteProfile: RemoteProfile {
    public static let reportID: UInt32 = 0xFB

    /// Bit i of the 16-bit little-endian payload ⇒ `bitOrder[i]`. Straight from the report descriptor:
    /// 0x60 TV, 0xE9 Vol+, 0xEA Vol−, 0x80 Select, 0x30 Power, 0x04 Siri, GD 0x86 Back, 0xE2 Mute,
    /// 0xCD Play/Pause, 0x42 Up, 0x45 Right, 0x43 Down, 0x44 Left.
    public static let bitOrder: [RemoteButton] = [
        .tv, .volumeUp, .volumeDown, .select, .power, .siri, .back, .mute,
        .playPause, .up, .right, .down, .left,
    ]

    public let generation: RemoteGeneration
    public let buttonUsagePage = 0x0C
    public let buttonUsage = 0x01
    public let buttons: [RemoteButton] = [
        .power, .back, .tv, .select, .up, .down, .left, .right, .playPause, .mute, .volumeUp, .volumeDown, .siri,
    ]

    public init(generation: RemoteGeneration = .gen3) {
        precondition(generation.hasClickpad, "ClickpadRemoteProfile only fits gen 2/3 remotes")
        self.generation = generation
    }

    public func decode(reportID: UInt32, bytes: [UInt8]) -> ButtonMask? {
        guard reportID == Self.reportID else { return nil }
        // IOKit hands us the report ID as byte 0; tolerate a payload without it too.
        let payload: ArraySlice<UInt8>
        if bytes.count >= 3, bytes[0] == UInt8(Self.reportID) {
            payload = bytes[1...]
        } else if bytes.count == 2 {
            payload = bytes[...]
        } else {
            return nil
        }
        let raw = UInt16(payload[payload.startIndex]) | (UInt16(payload[payload.startIndex + 1]) << 8)
        var mask = ButtonMask()
        for (bit, button) in Self.bitOrder.enumerated() where raw & (1 << UInt16(bit)) != 0 {
            mask.insert(button.mask)
        }
        return mask
    }
}

public enum RemoteProfiles {
    /// The profile for a generation, or nil when we have no verified layout (gen 1 has not been captured).
    public static func profile(for generation: RemoteGeneration) -> (any RemoteProfile)? {
        switch generation {
        case .gen2, .gen3: ClickpadRemoteProfile(generation: generation)
        case .gen1, .unknown: nil
        }
    }
}
