import AppKit
import Foundation
import IOKit
import IOKit.hid
import Observation
import RemoteCore
import os

/// Owns the `IOHIDManager`, tracks which remotes are connected, decodes their button reports, and runs
/// the gesture recognizers.
///
/// The manager is scheduled on the main run loop, so every IOKit callback lands on the main thread
/// and we can hop straight back onto the main actor. Device match / removal callbacks *are* the
/// connection-state feature — there is no polling anywhere.
///
/// A physical remote publishes several `IOHIDDevice`s (buttons, digitizer, sensors…); they share a
/// serial number, so everything is keyed by that and a remote stays "connected" while any remain.
@MainActor
@Observable
final class HIDRemoteMonitor {
    private(set) var remotes: [RemoteDevice] = []
    private(set) var ignoredDevices: [IgnoredHIDDevice] = []
    /// History behind the live panel: gestures, actions, connections, raw reports.
    let activity = ActivityLog()
    private(set) var inputMonitoring: InputMonitoringStatus = .notDetermined
    private(set) var isRunning = false
    /// Number of sub-devices currently opened with `kIOHIDOptionsTypeSeizeDevice`.
    private(set) var seizedDeviceCount = 0
    /// Accessibility trust — needed to post keystrokes and media keys.
    private(set) var accessibilityTrusted = AccessibilityPermission.isTrusted()

    let settings: AppSettings

    var connectedRemotes: [RemoteDevice] { remotes.filter(\.isConnected) }
    var hasConnectedRemote: Bool { remotes.contains(where: \.isConnected) }
    /// True when a binding posts synthetic input but we cannot post events yet.
    var needsAccessibility: Bool { !accessibilityTrusted && remotes.contains { $0.bindings.requiresAccessibility } }

    @ObservationIgnored private var manager: IOHIDManager?
    @ObservationIgnored private var handles: [DeviceKey: DeviceHandle] = [:]
    @ObservationIgnored private var ignoredKeys: [DeviceKey: String] = [:]
    @ObservationIgnored private var drivers: [String: GestureDriver] = [:]
    @ObservationIgnored private var profiles: [String: any RemoteProfile] = [:]
    @ObservationIgnored private let holds = HoldController()
    @ObservationIgnored private let store: RemoteStore
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TvRemoteControl", category: "hid")

    /// IOHIDManager hands us the same `IOHIDDevice` object for match and removal, so its address is
    /// a reliable key for the lifetime of the connection.
    typealias DeviceKey = UnsafeMutableRawPointer

    init(settings: AppSettings, store: RemoteStore = RemoteStore()) {
        self.settings = settings
        self.store = store
        remotes = store.load().map(RemoteDevice.init(record:))
        settings.onChange = { [weak self] in self?.applySettings() }
    }

    /// Whether `IOHIDDeviceOpen` should seize right now.
    private var wantsSeize: Bool { settings.isEnabled && settings.exclusiveMode }

    // MARK: Lifecycle

    func start() {
        guard manager == nil else { return }
        refreshPermission()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Match both Apple vendor IDs (USB-IF 0x05AC and Bluetooth SIG 0x004C — the remote uses the latter);
        // product-level classification happens in-process so a misclassified device stays visible.
        let matching = SiriRemoteIdentity.appleVendorIDs.map { [kIOHIDVendorIDKey: $0] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager
        isRunning = true
        logger.info("HID monitor started")
    }

    func stop() {
        guard let manager else { return }
        for (_, handle) in handles { close(handle) }
        handles.removeAll()
        ignoredKeys.removeAll()
        ignoredDevices.removeAll()
        for driver in drivers.values { driver.reset() }
        holds.endAll()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = nil
        for index in remotes.indices {
            remotes[index].isConnected = false
            remotes[index].isSeized = false
            remotes[index].heldButtons = []
        }
        isRunning = false
    }

    // MARK: Permissions

    func refreshPermission() {
        let status = InputMonitoringPermission.status()
        if status != inputMonitoring {
            logger.info("Input Monitoring: \(String(describing: status))")
            inputMonitoring = status
        }
        if status == .granted { reopenClosedDevices() }
        let trusted = AccessibilityPermission.isTrusted()
        if trusted != accessibilityTrusted {
            logger.info("Accessibility trusted: \(trusted)")
            accessibilityTrusted = trusted
        }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        refreshPermission()
    }

    /// Triggers the system prompt (only shown once per app signature); the result lands via `refreshPermission`.
    func requestPermission() {
        InputMonitoringPermission.request()
        refreshPermission()
    }

    // MARK: Settings

    /// Re-apply thresholds and exclusive mode to live devices.
    func applySettings() {
        for remote in remotes { drivers[remote.id]?.config = driverConfig(for: remote) }
        for handle in handles.values where handle.isOpen && handle.isSeized != wantsSeize {
            reopen(handle)
        }
        if !settings.isEnabled {
            holds.endAll()
            for driver in drivers.values { driver.reset() }
            for index in remotes.indices { remotes[index].heldButtons = [] }
        }
    }

    // MARK: Bindings

    func setBinding(remoteID: String, button: RemoteButton, gesture: ButtonGesture, binding: GestureBinding?) {
        guard let index = remotes.firstIndex(where: { $0.id == remoteID }) else { return }
        holds.end(key: HoldController.key(remoteID: remoteID, button: button.rawValue))
        remotes[index].bindings[button, gesture] = binding
        drivers[remoteID]?.config = driverConfig(for: remotes[index])
        persist()
        logger.info("Binding \(remoteID, privacy: .public) \(button.displayName, privacy: .public)/\(gesture.rawValue, privacy: .public) → \(binding?.action.displayString ?? "none", privacy: .public)\(binding?.holdUntilRelease == true ? " (hold)" : "", privacy: .public)")
    }

    func resetBindings(remoteID: String) {
        guard let index = remotes.firstIndex(where: { $0.id == remoteID }) else { return }
        holds.endAll(prefix: remoteID)
        let buttons = RemoteProfiles.profile(for: remotes[index].generation)?.buttons ?? []
        remotes[index].bindings = BindingSet.defaults(for: buttons)
        drivers[remoteID]?.config = driverConfig(for: remotes[index])
        persist()
    }

    /// Global thresholds plus this remote's deferred-press set (buttons that have a double-press binding).
    private func driverConfig(for remote: RemoteDevice) -> GestureConfig {
        var config = settings.gestureConfig
        config.deferredPressButtons = remote.bindings.buttonsWithDoublePress
        return config
    }

    // MARK: Device callbacks (main thread)

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        let info = HIDDeviceInfo(device: device)
        let key = Self.key(for: device)

        switch SiriRemoteIdentity.classify(info) {
        case .ignored(let reason):
            ignoredKeys[key] = info.stableID
            ignoredDevices.append(IgnoredHIDDevice(id: "\(info.stableID)#\(key.hashValue)", info: info, reason: reason))
            logger.debug("Ignoring \(info.product, privacy: .public) pid=\(info.productID) transport=\(info.transport, privacy: .public): \(reason, privacy: .public)")

        case .remote(let generation):
            let id = info.stableID
            logger.info("Remote matched: \(info.product, privacy: .public) pid=0x\(String(info.productID, radix: 16), privacy: .public) usage=\(info.primaryUsagePage)/\(info.primaryUsage) serial=\(info.serialNumber ?? "-", privacy: .public)")

            let profile = profiles[id] ?? RemoteProfiles.profile(for: generation)
            if let profile { profiles[id] = profile }
            if drivers[id] == nil {
                drivers[id] = GestureDriver(config: settings.gestureConfig) { [weak self] events in
                    self?.dispatch(events, remoteID: id)
                }
            }

            let handle = DeviceHandle(
                device: device, remoteID: id, maxReportSize: info.maxInputReportSize,
                usagePage: info.primaryUsagePage, usage: info.primaryUsage, monitor: self)
            handle.isButtonDevice = profile.map { $0.buttonUsagePage == info.primaryUsagePage && $0.buttonUsage == info.primaryUsage } ?? false
            handles[key] = handle

            var remote: RemoteDevice
            var wasConnected = false
            if let index = remotes.firstIndex(where: { $0.id == id }) {
                remote = remotes[index]
                wasConnected = remote.isConnected
                remote.update(from: info, generation: generation)
                remotes.remove(at: index)
            } else {
                remote = RemoteDevice(info: info, generation: generation)
            }
            remote.isConnected = true
            remote.hasProfile = profile != nil
            remote.openError = nil

            let result = open(handle)
            if result != kIOReturnSuccess {
                remote.openError = describeIOReturn(result)
                logger.error("IOHIDDeviceOpen failed for \(info.product, privacy: .public): \(describeIOReturn(result), privacy: .public)")
            }
            remote.isSeized = isSeized(remoteID: id)
            drivers[id]?.config = driverConfig(for: remote)
            if !wasConnected {
                activity.log(.device, remoteID: id, "\(remote.displayName) connected",
                             detail: remote.openError.map { "can't read input — \($0)" } ?? remote.generation.displayName,
                             isError: remote.openError != nil)
            }
            remotes.insert(remote, at: 0)
            persist()
        }
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        let key = Self.key(for: device)
        if let ignoredID = ignoredKeys.removeValue(forKey: key) {
            ignoredDevices.removeAll { $0.id.hasPrefix(ignoredID) }
            return
        }
        guard let handle = handles.removeValue(forKey: key) else { return }
        close(handle)
        logger.info("Remote sub-device removed: \(handle.remoteID, privacy: .public) usage=\(handle.usagePage)/\(handle.usage)")

        guard let index = remotes.firstIndex(where: { $0.id == handle.remoteID }) else { return }
        let stillConnected = handles.values.contains { $0.remoteID == handle.remoteID }
        if !stillConnected {
            drivers[handle.remoteID]?.reset()
            holds.endAll(prefix: handle.remoteID)
        }
        if remotes[index].isPersistent || stillConnected {
            remotes[index].isConnected = stillConnected
            remotes[index].isSeized = isSeized(remoteID: handle.remoteID)
            remotes[index].lastSeenAt = .now
            remotes[index].openError = nil
            if !stillConnected {
                remotes[index].heldButtons = []
                activity.log(.device, remoteID: handle.remoteID, "\(remotes[index].displayName) disconnected")
            }
        } else {
            remotes.remove(at: index)
            drivers[handle.remoteID] = nil
            profiles[handle.remoteID] = nil
        }
        persist()
    }

    fileprivate func inputReport(from handle: DeviceHandle, reportID: UInt32, bytes: [UInt8]) {
        guard let index = remotes.firstIndex(where: { $0.id == handle.remoteID }) else { return }
        let snapshot = HIDReportSnapshot(
            reportID: reportID, bytes: bytes, sourceUsagePage: handle.usagePage, sourceUsage: handle.usage)
        remotes[index].lastInputAt = .now
        remotes[index].lastReport = snapshot
        remotes[index].inputCount += 1
        if let battery = HIDDeviceInfo.batteryPercent(of: handle.device) {
            remotes[index].batteryPercent = battery
        }
        logger.debug("report \(handle.usagePage)/\(handle.usage) id=\(reportID) len=\(bytes.count): \(snapshot.hex, privacy: .public)")
        activity.log(.report, remoteID: handle.remoteID, "\(snapshot.sourceLabel) · id \(reportID)", detail: snapshot.hex)

        guard handle.isButtonDevice, settings.isEnabled,
              let profile = profiles[handle.remoteID],
              let mask = profile.decode(reportID: reportID, bytes: bytes) else { return }
        remotes[index].heldButtons = mask
        drivers[handle.remoteID]?.handle(mask: mask)
    }

    private func dispatch(_ events: [ButtonEvent], remoteID: String) {
        guard !events.isEmpty, let index = remotes.firstIndex(where: { $0.id == remoteID }) else { return }
        for event in events {
            logger.info("\(remoteID, privacy: .public): \(event.button.displayName, privacy: .public) \(event.gesture.displayName, privacy: .public)")
            activity.log(.gesture, remoteID: remoteID, "\(event.button.displayName) · \(event.gesture.displayName)",
                         detail: event.phase == .ended ? "released" : nil)
        }
        remotes[index].recentEvents = Array((events.reversed() + remotes[index].recentEvents).prefix(RemoteDevice.recentEventLimit))
        remotes[index].eventCount += events.count

        for event in events {
            guard let binding = remotes[index].bindings[event.button, event.gesture] else { continue }
            let spec = binding.action
            let holdKey = HoldController.key(remoteID: remoteID, button: event.button.rawValue)
            let isHold = event.gesture == .longPress && binding.holdUntilRelease

            if event.phase == .ended {
                // Only a held long press cares about the release.
                guard isHold, holds.isHolding(holdKey) else { continue }
                holds.end(key: holdKey)
                setFeedback(&remotes[index], ActionFeedback(button: event.button, gesture: event.gesture, summary: "released \(spec.displayString)"))
                continue
            }
            if case .mediaKey(let key) = spec, key == event.button.nativeMediaKey, !remotes[index].isSeized {
                // macOS already acted on this button itself; replaying it would double-step the volume.
                setFeedback(&remotes[index], ActionFeedback(button: event.button, gesture: event.gesture, summary: "\(spec.displayString) — handled by macOS (not seized)"))
                continue
            }
            let failureHandler: ActionFailureHandler = { [weak self] message in
                guard let self, let index = self.remotes.firstIndex(where: { $0.id == remoteID }) else { return }
                self.setFeedback(&self.remotes[index], ActionFeedback(button: event.button, gesture: event.gesture, summary: spec.displayString, error: message))
                self.logger.error("Action \(spec.displayString, privacy: .public) failed later: \(message, privacy: .public)")
            }
            do {
                if isHold, let holdable = spec.makeAction() as? any HoldableAction {
                    try holds.begin(key: holdKey, action: holdable)
                    setFeedback(&remotes[index], ActionFeedback(button: event.button, gesture: event.gesture, summary: "holding \(spec.displayString)"))
                } else {
                    try spec.makeAction(failureHandler: failureHandler).perform()
                    setFeedback(&remotes[index], ActionFeedback(button: event.button, gesture: event.gesture, summary: spec.displayString))
                }
                logger.info("Performed \(spec.displayString, privacy: .public) for \(event.button.displayName, privacy: .public) \(event.gesture.rawValue, privacy: .public)\(isHold ? " (hold)" : "", privacy: .public)")
            } catch {
                setFeedback(&remotes[index], ActionFeedback(button: event.button, gesture: event.gesture, summary: spec.displayString, error: error.localizedDescription))
                logger.error("Action \(spec.displayString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// One place to record what an action did, so the panel's last-action line and the log never disagree.
    private func setFeedback(_ remote: inout RemoteDevice, _ feedback: ActionFeedback) {
        remote.lastAction = feedback
        var title = "\(feedback.button.displayName) \(feedback.gesture.displayName.lowercased()) → \(feedback.summary)"
        if let error = feedback.error { title += " — \(error)" }
        activity.log(.action, remoteID: remote.id, title, isError: feedback.error != nil)
    }

    // MARK: Opening / closing

    private func open(_ handle: DeviceHandle) -> IOReturn {
        var result: IOReturn = kIOReturnSuccess
        if wantsSeize {
            result = IOHIDDeviceOpen(handle.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if result == kIOReturnSuccess {
                handle.isSeized = true
            } else {
                logger.warning("Seize failed for \(handle.remoteID, privacy: .public) usage=\(handle.usagePage)/\(handle.usage): \(describeIOReturn(result), privacy: .public) — opening shared instead")
            }
        }
        if !handle.isSeized {
            result = IOHIDDeviceOpen(handle.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard result == kIOReturnSuccess else { return result }
        handle.isOpen = true
        IOHIDDeviceRegisterInputReportCallback(
            handle.device, handle.buffer, handle.bufferSize, hidInputReport, Unmanaged.passUnretained(handle).toOpaque())
        updateSeizedCount()
        return result
    }

    private func close(_ handle: DeviceHandle) {
        guard handle.isOpen else { return }
        IOHIDDeviceRegisterInputReportCallback(handle.device, handle.buffer, handle.bufferSize, nil, nil)
        IOHIDDeviceClose(handle.device, IOOptionBits(kIOHIDOptionsTypeNone))
        handle.isOpen = false
        handle.isSeized = false
        updateSeizedCount()
    }

    private func reopen(_ handle: DeviceHandle) {
        close(handle)
        let result = open(handle)
        guard let index = remotes.firstIndex(where: { $0.id == handle.remoteID }) else { return }
        remotes[index].openError = result == kIOReturnSuccess ? nil : describeIOReturn(result)
        remotes[index].isSeized = isSeized(remoteID: handle.remoteID)
    }

    /// After Input Monitoring is granted, devices that were matched while it was missing still need opening.
    private func reopenClosedDevices() {
        for handle in handles.values where !handle.isOpen {
            let result = open(handle)
            guard let index = remotes.firstIndex(where: { $0.id == handle.remoteID }) else { continue }
            remotes[index].openError = result == kIOReturnSuccess ? nil : describeIOReturn(result)
            remotes[index].isSeized = isSeized(remoteID: handle.remoteID)
        }
    }

    private func isSeized(remoteID: String) -> Bool {
        handles.values.contains { $0.remoteID == remoteID && $0.isSeized }
    }

    private func updateSeizedCount() {
        let count = handles.values.filter(\.isSeized).count
        if count != seizedDeviceCount { seizedDeviceCount = count }
    }

    private func persist() {
        store.save(remotes.filter(\.isPersistent).map(RemoteRecord.init(remote:)))
    }

    private static func key(for device: IOHIDDevice) -> DeviceKey {
        Unmanaged.passUnretained(device).toOpaque()
    }
}

/// Per-sub-device state: the buffer IOKit fills with each input report, plus open state.
@MainActor
final class DeviceHandle {
    let device: IOHIDDevice
    let remoteID: String
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferSize: Int
    /// Primary usage of this sub-device — the remote exposes several (consumer control, digitizer, sensors…).
    let usagePage: Int
    let usage: Int
    /// True for the sub-device whose reports the remote's profile decodes.
    var isButtonDevice = false
    var isOpen = false
    var isSeized = false
    weak var monitor: HIDRemoteMonitor?

    init(device: IOHIDDevice, remoteID: String, maxReportSize: Int, usagePage: Int, usage: Int, monitor: HIDRemoteMonitor) {
        self.device = device
        self.remoteID = remoteID
        self.usagePage = usagePage
        self.usage = usage
        self.monitor = monitor
        bufferSize = max(maxReportSize, 8)
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }
}

/// An Apple HID device we matched but decided is not a remote. Shown in a debug disclosure so a
/// misclassified remote is visible rather than silently missing.
struct IgnoredHIDDevice: Identifiable, Equatable {
    let id: String
    let info: HIDDeviceInfo
    let reason: String
}

// MARK: - C callbacks

private nonisolated func hidDeviceMatched(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice) {
    guard let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.deviceMatched(device) }
}

private nonisolated func hidDeviceRemoved(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice) {
    guard let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.deviceRemoved(device) }
}

private nonisolated func hidInputReport(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType, _ reportID: UInt32, _ report: UnsafeMutablePointer<UInt8>, _ reportLength: CFIndex) {
    guard let context, result == kIOReturnSuccess else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    let handle = Unmanaged<DeviceHandle>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { handle.monitor?.inputReport(from: handle, reportID: reportID, bytes: bytes) }
}
