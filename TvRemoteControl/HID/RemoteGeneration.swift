import Foundation
import RemoteCore

extension RemoteGeneration {
    /// SF Symbols draws the 2015 touch-surface remote as `gen3` and the 2021 clickpad remote as `gen4`.
    var symbolName: String {
        switch self {
        case .gen1: "appletvremote.gen3"
        case .gen2, .gen3, .unknown: "appletvremote.gen4"
        }
    }
}

extension RemoteButton {
    var symbolName: String {
        switch self {
        case .power: "power"
        case .back: "chevron.backward"
        case .tv: "tv"
        case .select: "circle.inset.filled"
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .playPause: "playpause"
        case .mute: "speaker.slash"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .siri: "mic"
        }
    }
}

/// How we decide whether an Apple HID device is a Siri Remote.
enum SiriRemoteIdentity {
    /// Apple's USB-IF vendor ID — what Apple's own drivers stamp on AirPods (AACP) and internal sensors.
    static let appleUSBVendorID = 0x05AC
    /// Apple's Bluetooth SIG company ID. HID-over-GATT devices publish the PnP ID from their Device
    /// Information Service, and the Siri Remote uses the Bluetooth SIG namespace (`VendorIDSource = 1`),
    /// so its IOHIDDevices carry 0x004C — not 0x05AC. Observed on real hardware; see BUTTONS.md.
    static let appleBluetoothVendorID = 0x004C
    static let appleVendorIDs = [appleUSBVendorID, appleBluetoothVendorID]

    /// Product IDs confirmed on real hardware by the Phase 0 spike (see BUTTONS.md). Nothing here is guessed.
    static let knownProductIDs: [Int: RemoteGeneration] = [
        0x0315: .gen3, // A2854 (USB-C) clickpad remote, serial C08N44382330, captured 2026-08-25
    ]

    /// Apple Bluetooth HID peripherals that are definitely not a remote.
    private static let nonRemoteNameFragments = ["magic", "keyboard", "mouse", "trackpad", "airpods", "beats", "pencil"]

    enum Classification: Equatable {
        case remote(RemoteGeneration)
        case ignored(reason: String)
    }

    static func classify(_ info: HIDDeviceInfo) -> Classification {
        guard appleVendorIDs.contains(info.vendorID) else {
            return .ignored(reason: "vendor 0x\(String(format: "%04X", info.vendorID)) is not Apple")
        }
        if let generation = knownProductIDs[info.productID] {
            return .remote(generation)
        }
        guard info.isBluetooth else {
            return .ignored(reason: "transport \(info.transport)")
        }
        let name = info.product.lowercased()
        if let fragment = nonRemoteNameFragments.first(where: { name.contains($0) }) {
            return .ignored(reason: "name contains “\(fragment)”")
        }
        // An Apple Bluetooth HID device with an unrecorded PID (e.g. a gen 1 remote) is shown as a
        // candidate so it can be identified, but its reports are not decoded until BUTTONS.md has it.
        return .remote(.unknown)
    }
}
