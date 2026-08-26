import Foundation
import Observation
import RemoteCore

/// User-tunable behaviour, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let exclusiveMode = "exclusiveMode"
        static let longPressMilliseconds = "longPressMilliseconds"
        static let doublePressMilliseconds = "doublePressMilliseconds"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Invoked after any change so the HID layer can re-apply it (re-open devices, retune recognizers).
    @ObservationIgnored var onChange: (() -> Void)?

    /// Global kill switch: when off, nothing is decoded and no device is seized.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled); onChange?() }
    }

    /// Open remotes with `kIOHIDOptionsTypeSeizeDevice`, which stops macOS from acting on Volume/Mute/
    /// Play-Pause itself (the Phase 0 decision). Off by default until bindings exist, otherwise the
    /// remote's volume buttons would simply stop working.
    var exclusiveMode: Bool {
        didSet { defaults.set(exclusiveMode, forKey: Key.exclusiveMode); onChange?() }
    }

    var longPressMilliseconds: Int {
        didSet { defaults.set(longPressMilliseconds, forKey: Key.longPressMilliseconds); onChange?() }
    }

    var doublePressMilliseconds: Int {
        didSet { defaults.set(doublePressMilliseconds, forKey: Key.doublePressMilliseconds); onChange?() }
    }

    var gestureConfig: GestureConfig {
        GestureConfig(longPressThreshold: Double(longPressMilliseconds) / 1000,
                      doublePressInterval: Double(doublePressMilliseconds) / 1000)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.exclusiveMode: false,
            Key.longPressMilliseconds: 500,
            Key.doublePressMilliseconds: 300,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        exclusiveMode = defaults.bool(forKey: Key.exclusiveMode)
        longPressMilliseconds = defaults.integer(forKey: Key.longPressMilliseconds)
        doublePressMilliseconds = defaults.integer(forKey: Key.doublePressMilliseconds)
    }
}
