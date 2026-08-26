import Foundation
import IOKit
import IOKit.hid

/// Identifying properties of an `IOHIDDevice`, read once when the device matches.
struct HIDDeviceInfo: Equatable, Sendable {
    var product: String
    var manufacturer: String
    var transport: String
    var serialNumber: String?
    var vendorID: Int
    var productID: Int
    var versionNumber: Int
    var primaryUsagePage: Int
    var primaryUsage: Int
    var maxInputReportSize: Int
    var registryEntryID: UInt64
    var batteryPercent: Int?

    var isBluetooth: Bool { transport.lowercased().hasPrefix("bluetooth") }

    /// True when the device exposes a serial number we can key persisted state on.
    var hasStableIdentity: Bool { !(serialNumber ?? "").isEmpty }

    /// Serial number when present, else the IORegistry entry ID (which changes on every reconnect —
    /// such devices are treated as transient and not persisted).
    var stableID: String {
        hasStableIdentity ? "serial:\(serialNumber!)" : "registry:\(registryEntryID)"
    }

    nonisolated init(device: IOHIDDevice) {
        func string(_ key: String) -> String? { IOHIDDeviceGetProperty(device, key as CFString) as? String }
        func int(_ key: String) -> Int? { IOHIDDeviceGetProperty(device, key as CFString) as? Int }

        product = string(kIOHIDProductKey) ?? ""
        manufacturer = string(kIOHIDManufacturerKey) ?? ""
        transport = string(kIOHIDTransportKey) ?? ""
        serialNumber = string(kIOHIDSerialNumberKey)
        vendorID = int(kIOHIDVendorIDKey) ?? 0
        productID = int(kIOHIDProductIDKey) ?? 0
        versionNumber = int(kIOHIDVersionNumberKey) ?? 0
        primaryUsagePage = int(kIOHIDPrimaryUsagePageKey) ?? 0
        primaryUsage = int(kIOHIDPrimaryUsageKey) ?? 0
        maxInputReportSize = int(kIOHIDMaxInputReportSizeKey) ?? 64
        registryEntryID = Self.registryEntryID(of: device)
        batteryPercent = Self.batteryPercent(of: device)
    }

    nonisolated static func registryEntryID(of device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        if service != MACH_PORT_NULL {
            IORegistryEntryGetRegistryEntryID(service, &id)
        }
        return id
    }

    /// Opportunistic: Apple's Bluetooth HID driver publishes this for Magic peripherals; the spike
    /// will tell us whether the remote gets it too. Nil when absent.
    nonisolated static func batteryPercent(of device: IOHIDDevice) -> Int? {
        IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString) as? Int
    }
}

/// Human-readable IOReturn for the handful of codes we expect from `IOHIDDeviceOpen`.
nonisolated func describeIOReturn(_ result: IOReturn) -> String {
    switch UInt32(bitPattern: result) {
    case 0x00000000: "success"
    case 0xE00002E2: "not permitted — Input Monitoring is not granted"
    case 0xE00002C5: "exclusive access — another process has seized the device"
    case 0xE00002C7: "unsupported"
    case 0xE00002CD: "not open"
    default: String(format: "IOReturn 0x%08x", UInt32(bitPattern: result))
    }
}
