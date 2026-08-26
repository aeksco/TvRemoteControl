// hidspike — Phase 0 throwaway HID dump tool for the Apple TV Siri Remote.
//
//   swift run hidspike [--seize] [--all] [--vendor 0xNNNN]
//
//   --seize        open remotes with kIOHIDOptionsTypeSeizeDevice (exclusive). Watch whether the
//                  system volume HUD still reacts to Volume Up/Down. Only ever applied to
//                  Bluetooth-transport devices, never to the built-in keyboard/trackpad.
//   --all          also dump + listen on non-Bluetooth matches (internal sensors etc.). Noisy.
//   --vendor 0x…   match only this vendor id (default: Apple USB-IF 0x05AC *and* Bluetooth SIG 0x004C).
//
// Input Monitoring must be granted to the *terminal app* this runs from
// (System Settings → Privacy & Security → Input Monitoring). Ctrl-C to quit.

import Foundation
import IOKit
import IOKit.hid

setvbuf(stdout, nil, _IONBF, 0) // keep output flowing when piped to tee or a file

// MARK: - Arguments

let arguments = Array(CommandLine.arguments.dropFirst())
let seize = arguments.contains("--seize")
let includeAll = arguments.contains("--all")
/// Apple has two vendor ids: the USB-IF one (0x05AC, used by AirPods/AACP and internal sensors) and the
/// Bluetooth SIG company id (0x004C). HID-over-GATT devices publish the PnP ID from their Device
/// Information Service, and the Siri Remote uses the Bluetooth SIG namespace (VendorIDSource = 1).
var vendorIDs = [0x05AC, 0x004C]
if let i = arguments.firstIndex(of: "--vendor"), i + 1 < arguments.count {
    let raw = arguments[i + 1]
    if let v = raw.hasPrefix("0x") ? Int(raw.dropFirst(2), radix: 16) : Int(raw) { vendorIDs = [v] }
}

// MARK: - Helpers

let startTime = Date()
func stamp() -> String { String(format: "%9.1f ms", Date().timeIntervalSince(startTime) * 1000) }

func property(_ device: IOHIDDevice, _ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
func string(_ device: IOHIDDevice, _ key: String) -> String { property(device, key) as? String ?? "–" }
func number(_ device: IOHIDDevice, _ key: String) -> Int? { property(device, key) as? Int }
func hex16(_ value: Int?) -> String { value.map { String(format: "0x%04X (%d)", $0, $0) } ?? "–" }
func hex(_ bytes: UnsafeBufferPointer<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }
func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined(separator: " ") }
func pad(_ s: String, _ width: Int) -> String { s.count >= width ? s : s + String(repeating: " ", count: width - s.count) }

func registryEntryID(_ device: IOHIDDevice) -> UInt64 {
    var id: UInt64 = 0
    let service = IOHIDDeviceGetService(device)
    if service != MACH_PORT_NULL { IORegistryEntryGetRegistryEntryID(service, &id) }
    return id
}

func isBluetooth(_ device: IOHIDDevice) -> Bool {
    string(device, kIOHIDTransportKey).lowercased().hasPrefix("bluetooth")
}

/// Every property on the device's IORegistry entry — this is where battery keys, addresses etc.
/// show up, whatever they happen to be called on this OS.
func registryProperties(_ device: IOHIDDevice) -> [String: Any] {
    let service = IOHIDDeviceGetService(device)
    guard service != MACH_PORT_NULL else { return [:] }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any] else { return [:] }
    return dict
}

func describe(_ result: IOReturn) -> String {
    switch UInt32(bitPattern: result) {
    case 0x00000000: return "success"
    case 0xE00002E2: return "kIOReturnNotPermitted — Input Monitoring not granted to this terminal"
    case 0xE00002C5: return "kIOReturnExclusiveAccess — another process has seized it"
    case 0xE00002C7: return "kIOReturnUnsupported"
    case 0xE00002CD: return "kIOReturnNotOpen"
    case 0xE00002C2: return "kIOReturnBadArgument"
    default: return String(format: "IOReturn 0x%08x", UInt32(bitPattern: result))
    }
}

func elementTypeName(_ type: IOHIDElementType) -> String {
    switch type {
    case kIOHIDElementTypeInput_Misc: return "in.misc"
    case kIOHIDElementTypeInput_Button: return "in.button"
    case kIOHIDElementTypeInput_Axis: return "in.axis"
    case kIOHIDElementTypeInput_ScanCodes: return "in.scancode"
    case kIOHIDElementTypeOutput: return "output"
    case kIOHIDElementTypeFeature: return "feature"
    case kIOHIDElementTypeCollection: return "collection"
    default: return "type\(type.rawValue)"
    }
}

func usagePageName(_ page: UInt32) -> String {
    switch page {
    case 0x01: return "GenericDesktop"
    case 0x06: return "GenericDeviceControls"
    case 0x07: return "Keyboard"
    case 0x08: return "LED"
    case 0x09: return "Button"
    case 0x0C: return "Consumer"
    case 0x0D: return "Digitizer"
    case 0x20: return "Sensor"
    case 0xFF00...0xFFFF: return "Vendor"
    default: return "page\(page)"
    }
}

func usageName(page: UInt32, usage: UInt32) -> String {
    switch (page, usage) {
    case (0x01, 0x01): return "Pointer"
    case (0x01, 0x02): return "Mouse"
    case (0x01, 0x06): return "Keyboard"
    case (0x01, 0x30): return "X"
    case (0x01, 0x31): return "Y"
    case (0x01, 0x38): return "Wheel"
    case (0x01, 0x39): return "HatSwitch"
    case (0x01, 0x80): return "SystemControl"
    case (0x01, 0x81): return "SystemPowerDown"
    case (0x01, 0x82): return "SystemSleep"
    case (0x01, 0x83): return "SystemWakeUp"
    case (0x06, 0x20): return "BatteryStrength"
    case (0x0C, 0x01): return "ConsumerControl"
    case (0x0C, 0x30): return "Power"
    case (0x0C, 0x40): return "Menu"
    case (0x0C, 0x41): return "MenuPick"
    case (0x0C, 0x42): return "MenuUp"
    case (0x0C, 0x43): return "MenuDown"
    case (0x0C, 0x44): return "MenuLeft"
    case (0x0C, 0x45): return "MenuRight"
    case (0x0C, 0x46): return "MenuEscape"
    case (0x0C, 0x9C): return "ChannelIncrement"
    case (0x0C, 0x9D): return "ChannelDecrement"
    case (0x0C, 0xB0): return "Play"
    case (0x0C, 0xB1): return "Pause"
    case (0x0C, 0xB3): return "FastForward"
    case (0x0C, 0xB4): return "Rewind"
    case (0x0C, 0xB5): return "ScanNextTrack"
    case (0x0C, 0xB6): return "ScanPreviousTrack"
    case (0x0C, 0xB7): return "Stop"
    case (0x0C, 0xCD): return "PlayPause"
    case (0x0C, 0xCF): return "VoiceCommand"
    case (0x0C, 0xE2): return "Mute"
    case (0x0C, 0xE9): return "VolumeIncrement"
    case (0x0C, 0xEA): return "VolumeDecrement"
    case (0x0C, 0x221): return "AC_Search"
    case (0x0C, 0x223): return "AC_Home"
    case (0x0C, 0x224): return "AC_Back"
    case (0x0C, 0x225): return "AC_Forward"
    case (0x0C, 0x22A): return "AC_Bookmarks"
    case (0x07, _): return "Key"
    case (0x09, _): return "Button\(usage)"
    default: return ""
    }
}

func elementDepth(_ element: IOHIDElement) -> Int {
    var depth = 0
    var parent = IOHIDElementGetParent(element)
    while let p = parent { depth += 1; parent = IOHIDElementGetParent(p) }
    return depth
}

// MARK: - Device dump

func dumpDevice(_ device: IOHIDDevice) {
    let page = number(device, kIOHIDPrimaryUsagePageKey) ?? 0
    let usage = number(device, kIOHIDPrimaryUsageKey) ?? 0
    print("┌─ DEVICE  registry entry id 0x\(String(registryEntryID(device), radix: 16))")
    print("│ product        : \(string(device, kIOHIDProductKey))")
    print("│ manufacturer   : \(string(device, kIOHIDManufacturerKey))")
    print("│ vendor id      : \(hex16(number(device, kIOHIDVendorIDKey)))")
    print("│ product id     : \(hex16(number(device, kIOHIDProductIDKey)))   ← record this in BUTTONS.md")
    print("│ version        : \(hex16(number(device, kIOHIDVersionNumberKey)))")
    print("│ serial number  : \(string(device, kIOHIDSerialNumberKey))")
    print("│ transport      : \(string(device, kIOHIDTransportKey))")
    print("│ primary usage  : page 0x\(String(page, radix: 16)) (\(usagePageName(UInt32(page)))) usage 0x\(String(usage, radix: 16)) \(usageName(page: UInt32(page), usage: UInt32(usage)))")
    print("│ max in report  : \(number(device, kIOHIDMaxInputReportSizeKey) ?? -1) bytes")
    if let pairs = property(device, kIOHIDDeviceUsagePairsKey) as? [[String: Any]] {
        let rendered = pairs.map { p -> String in
            let pg = (p[kIOHIDDeviceUsagePageKey] as? Int) ?? 0
            let us = (p[kIOHIDDeviceUsageKey] as? Int) ?? 0
            return "0x\(String(pg, radix: 16))/0x\(String(us, radix: 16)) \(usageName(page: UInt32(pg), usage: UInt32(us)))"
        }
        print("│ usage pairs    : \(rendered.joined(separator: ", "))")
    }

    print("│ registry properties:")
    let props = registryProperties(device)
    for key in props.keys.sorted() {
        let value = props[key]!
        var rendered: String
        if let data = value as? Data {
            rendered = key == kIOHIDReportDescriptorKey || data.count <= 64
                ? "<\(data.count) bytes> \(hex(data))"
                : "<\(data.count) bytes> \(hex(data.prefix(64)))…"
        } else {
            rendered = String(describing: value).replacingOccurrences(of: "\n", with: " ")
            if rendered.count > 240 { rendered = String(rendered.prefix(240)) + "…" }
        }
        print("│   \(pad(key, 34)) = \(rendered)")
    }

    print("│ elements:")
    if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
        for element in elements {
            let type = IOHIDElementGetType(element)
            let pg = IOHIDElementGetUsagePage(element)
            let us = IOHIDElementGetUsage(element)
            var line = "│   " + String(repeating: "  ", count: elementDepth(element)) + pad(elementTypeName(type), 12)
            line += " page 0x\(String(format: "%02X", pg)) usage 0x\(String(format: "%02X", us))"
            let name = usageName(page: pg, usage: us)
            line += " " + pad(name.isEmpty ? usagePageName(pg) : name, 18)
            if type == kIOHIDElementTypeCollection {
                line += "  (collection type \(IOHIDElementGetCollectionType(element).rawValue))"
            } else {
                line += "  reportID \(IOHIDElementGetReportID(element))"
                line += "  bits \(IOHIDElementGetReportSize(element))×\(IOHIDElementGetReportCount(element))"
                line += "  logical \(IOHIDElementGetLogicalMin(element))…\(IOHIDElementGetLogicalMax(element))"
            }
            line += "  cookie \(IOHIDElementGetCookie(element))"
            print(line)
        }
    } else {
        print("│   (could not enumerate elements)")
    }
    print("└─")
}

// MARK: - Listening

final class Listener {
    let device: IOHIDDevice
    let tag: String
    let bufferSize: Int
    let buffer: UnsafeMutablePointer<UInt8>
    init(device: IOHIDDevice, tag: String) {
        self.device = device
        self.tag = tag
        bufferSize = max(number(device, kIOHIDMaxInputReportSizeKey) ?? 64, 8)
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }
    deinit { buffer.deallocate() }
}

var listeners: [UnsafeMutableRawPointer: Listener] = [:]
func key(_ device: IOHIDDevice) -> UnsafeMutableRawPointer { Unmanaged.passUnretained(device).toOpaque() }

let inputReportCallback: IOHIDReportCallback = { context, _, _, type, reportID, report, length in
    guard let context else { return }
    let listener = Unmanaged<Listener>.fromOpaque(context).takeUnretainedValue()
    let bytes = UnsafeBufferPointer(start: report, count: length)
    print("[\(stamp())] \(listener.tag)  REPORT id=\(reportID) type=\(type.rawValue) len=\(length):  \(hex(bytes))")
}

let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    let listener = Unmanaged<Listener>.fromOpaque(context).takeUnretainedValue()
    let element = IOHIDValueGetElement(value)
    let pg = IOHIDElementGetUsagePage(element)
    let us = IOHIDElementGetUsage(element)
    let name = usageName(page: pg, usage: us)
    print("[\(stamp())] \(listener.tag)  VALUE  page 0x\(String(format: "%02X", pg)) usage 0x\(String(format: "%02X", us)) \(name.isEmpty ? usagePageName(pg) : name) = \(IOHIDValueGetIntegerValue(value))  (reportID \(IOHIDElementGetReportID(element)))")
}

let matchingCallback: IOHIDDeviceCallback = { _, _, _, device in
    let bluetooth = isBluetooth(device)
    let tag = "\(string(device, kIOHIDProductKey)) pid=\(hex16(number(device, kIOHIDProductIDKey))) [0x\(String(registryEntryID(device), radix: 16))]"
    guard bluetooth || includeAll else {
        print("[\(stamp())] skip (transport \(string(device, kIOHIDTransportKey))): \(tag)")
        return
    }
    print("[\(stamp())] MATCHED \(tag)")
    dumpDevice(device)

    let seizing = seize && bluetooth
    let options = seizing ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
    let result = IOHIDDeviceOpen(device, options)
    print("[\(stamp())] open(\(seizing ? "SEIZE" : "shared")) \(tag) → \(describe(result))")
    guard result == kIOReturnSuccess else { return }

    let listener = Listener(device: device, tag: tag)
    listeners[key(device)] = listener
    let context = Unmanaged.passUnretained(listener).toOpaque()
    IOHIDDeviceRegisterInputReportCallback(device, listener.buffer, listener.bufferSize, inputReportCallback, context)
    IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, context)
    print("[\(stamp())] listening on \(tag) — press buttons now")
}

let removalCallback: IOHIDDeviceCallback = { _, _, _, device in
    if let listener = listeners.removeValue(forKey: key(device)) {
        print("[\(stamp())] REMOVED \(listener.tag)")
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceRegisterInputReportCallback(device, listener.buffer, listener.bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    } else {
        print("[\(stamp())] REMOVED \(string(device, kIOHIDProductKey)) [0x\(String(registryEntryID(device), radix: 16))]")
    }
}

// MARK: - Main

print("hidspike — matching vendor ids \(vendorIDs.map { String(format: "0x%04X", $0) }.joined(separator: ", "))\(seize ? " — SEIZE mode" : "")\(includeAll ? " — including non-Bluetooth devices" : "")")
switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
case kIOHIDAccessTypeGranted:
    print("Input Monitoring: granted")
case kIOHIDAccessTypeDenied:
    print("Input Monitoring: DENIED for this terminal — enable it in System Settings → Privacy & Security → Input Monitoring, then rerun")
default:
    print("Input Monitoring: not determined — requesting (a system prompt should appear)")
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatchingMultiple(manager, vendorIDs.map { [kIOHIDVendorIDKey: $0] as CFDictionary } as CFArray)
IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
print("Waiting for devices. Ctrl-C to quit.\n")
CFRunLoopRun()
