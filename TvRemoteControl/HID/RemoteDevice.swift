import Foundation
import RemoteCore

/// A Siri Remote we have seen at least once. Lives in the UI list whether or not it is currently
/// connected; connection state flips from the IOHIDManager match/removal callbacks.
struct RemoteDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var generation: RemoteGeneration
    var vendorID: Int
    var productID: Int
    var serialNumber: String?
    var transport: String
    var registryEntryID: UInt64?
    var isPersistent: Bool

    var isConnected = false
    /// True when we have a verified report layout (`RemoteProfile`) for this generation.
    var hasProfile = false
    /// True while at least one of its sub-devices is opened exclusively (exclusive mode).
    var isSeized = false
    var batteryPercent: Int?
    /// Non-nil when the device is connected but `IOHIDDeviceOpen` failed (almost always: no Input Monitoring).
    var openError: String?

    var firstSeenAt: Date
    var lastSeenAt: Date
    var lastInputAt: Date?
    var lastReport: HIDReportSnapshot?
    var inputCount = 0

    /// Buttons currently held, from the latest decoded report.
    var heldButtons: ButtonMask = []
    /// Most recent gesture events, newest first.
    var recentEvents: [ButtonEvent] = []
    var eventCount = 0
    static let recentEventLimit = 5

    /// (button, gesture) → action. Persisted; editable while the remote is disconnected.
    var bindings = BindingSet()
    /// What the most recent bound gesture did (or failed to do), for visible feedback in the menu.
    var lastAction: ActionFeedback?

    /// The remote reports its serial number as its product name; show something friendlier.
    var displayName: String {
        name.isEmpty || name == serialNumber ? "Siri Remote" : name
    }

    var productIDHex: String {
        String(format: "0x%04X", productID)
    }
}

struct ActionFeedback: Equatable {
    var button: RemoteButton
    var gesture: ButtonGesture
    var summary: String
    var error: String?
    var at: Date = .now
}

struct HIDReportSnapshot: Equatable {
    var reportID: UInt32
    var bytes: [UInt8]
    var sourceUsagePage: Int
    var sourceUsage: Int

    /// Which of the remote's sub-devices produced this report.
    var sourceLabel: String {
        switch (sourceUsagePage, sourceUsage) {
        case (0x0C, 0x01): "buttons"
        case (0x0C, _): "consumer/\(sourceUsage)"
        case (0x0D, _): "touch"
        case (0x20, _): "sensor/\(sourceUsage)"
        case (0xFF00..., _): "vendor/\(sourceUsage)"
        default: "page \(sourceUsagePage)/\(sourceUsage)"
        }
    }

    var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

extension RemoteDevice {
    init(info: HIDDeviceInfo, generation: RemoteGeneration, now: Date = .now) {
        id = info.stableID
        name = info.product
        self.generation = generation
        vendorID = info.vendorID
        productID = info.productID
        serialNumber = info.serialNumber
        transport = info.transport
        registryEntryID = info.registryEntryID
        isPersistent = info.hasStableIdentity
        batteryPercent = info.batteryPercent
        firstSeenAt = now
        lastSeenAt = now
        bindings = BindingSet.defaults(for: RemoteProfiles.profile(for: generation)?.buttons ?? [])
    }

    /// Refresh the hardware-derived fields from a fresh match without losing history.
    mutating func update(from info: HIDDeviceInfo, generation: RemoteGeneration, now: Date = .now) {
        if !info.product.isEmpty { name = info.product }
        if generation != .unknown || self.generation == .unknown { self.generation = generation }
        vendorID = info.vendorID
        productID = info.productID
        serialNumber = info.serialNumber
        transport = info.transport
        registryEntryID = info.registryEntryID
        if let battery = info.batteryPercent { batteryPercent = battery }
        lastSeenAt = now
    }
}
