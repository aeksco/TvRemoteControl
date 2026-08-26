import Foundation

public enum ButtonGesture: String, Codable, CaseIterable, Sendable {
    case press        // fires on release, unless a long press already fired
    case longPress    // fires at the threshold while still held; reports `.ended` on release
    case doublePress  // two presses within the double-press interval

    public var displayName: String {
        switch self {
        case .press: "Press"
        case .longPress: "Long press"
        case .doublePress: "Double press"
        }
    }
}

/// Gestures fire once (`.began`). A long press additionally reports `.ended` when the button comes
/// back up, so an action can be held down for the duration.
public enum GesturePhase: String, Codable, Sendable {
    case began
    case ended
}

public struct ButtonEvent: Equatable, Sendable {
    public let button: RemoteButton
    public let gesture: ButtonGesture
    public let phase: GesturePhase
    /// Seconds on whatever clock the caller feeds into the recognizer.
    public let time: TimeInterval

    public init(button: RemoteButton, gesture: ButtonGesture, phase: GesturePhase = .began, time: TimeInterval) {
        self.button = button
        self.gesture = gesture
        self.phase = phase
        self.time = time
    }
}

public struct GestureConfig: Equatable, Sendable {
    public var longPressThreshold: TimeInterval
    public var doublePressInterval: TimeInterval
    /// Buttons whose single press waits for the double-press window before firing, so a double press
    /// does not also trigger the single-press binding. For buttons not in this set the single press
    /// fires immediately on release and a quick second tap fires `.doublePress` on top.
    public var deferredPressButtons: Set<RemoteButton>

    public init(longPressThreshold: TimeInterval = 0.5,
                doublePressInterval: TimeInterval = 0.3,
                deferredPressButtons: Set<RemoteButton> = []) {
        self.longPressThreshold = longPressThreshold
        self.doublePressInterval = doublePressInterval
        self.deferredPressButtons = deferredPressButtons
    }
}

/// Turns a stream of button masks into press / long-press / double-press events.
///
/// Pure and clock-agnostic: the caller passes timestamps into `handle(mask:at:)`, and must call
/// `tick(at:)` no later than `nextDeadline()` so that time-based gestures (long press, deferred single
/// press) fire while nothing is changing on the remote. Each button has its own state, so chords are
/// simply concurrent gestures.
public struct GestureRecognizer: Equatable, Sendable {
    public var config: GestureConfig
    public private(set) var held: ButtonMask = []
    private var states: [RemoteButton: ButtonState] = [:]

    private struct ButtonState: Equatable, Sendable {
        var pressedAt: TimeInterval?
        var longPressFired = false
        var isSecondTap = false
        var lastTapReleasedAt: TimeInterval?
        var pendingPressDeadline: TimeInterval?
        var pendingPressReleasedAt: TimeInterval?
    }

    /// Tolerance for deadline comparisons so `0.7 - 0.2 >= 0.5` holds despite floating-point rounding.
    private static let epsilon: TimeInterval = 1e-6

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    /// Feed a decoded report. Returns the events it produced, in order.
    public mutating func handle(mask: ButtonMask, at time: TimeInterval) -> [ButtonEvent] {
        var events = tick(at: time)
        let changed = mask.symmetricDifference(held)
        for button in RemoteButton.allCases where changed.contains(button) {
            if mask.contains(button) {
                press(button, at: time)
            } else {
                events += release(button, at: time)
            }
        }
        held = mask
        return events
    }

    /// Fire any time-based gestures that are due at `time`.
    public mutating func tick(at time: TimeInterval) -> [ButtonEvent] {
        var events: [ButtonEvent] = []
        for button in RemoteButton.allCases {
            guard var state = states[button] else { continue }
            if let deadline = state.pendingPressDeadline, time + Self.epsilon >= deadline {
                events.append(ButtonEvent(button: button, gesture: .press, time: state.pendingPressReleasedAt ?? deadline))
                state.pendingPressDeadline = nil
                state.pendingPressReleasedAt = nil
                state.lastTapReleasedAt = nil
            }
            if let pressedAt = state.pressedAt, !state.longPressFired, time - pressedAt + Self.epsilon >= config.longPressThreshold {
                state.longPressFired = true
                state.isSecondTap = false
                events.append(ButtonEvent(button: button, gesture: .longPress, time: pressedAt + config.longPressThreshold))
            }
            states[button] = state
        }
        return events
    }

    /// The earliest time at which `tick(at:)` would produce an event, or nil when nothing is pending.
    public func nextDeadline() -> TimeInterval? {
        var deadline: TimeInterval?
        for state in states.values {
            if let pending = state.pendingPressDeadline {
                deadline = min(deadline ?? pending, pending)
            }
            if let pressedAt = state.pressedAt, !state.longPressFired {
                let longPressAt = pressedAt + config.longPressThreshold
                deadline = min(deadline ?? longPressAt, longPressAt)
            }
        }
        return deadline
    }

    private mutating func press(_ button: RemoteButton, at time: TimeInterval) {
        var state = states[button] ?? ButtonState()
        state.pressedAt = time
        state.longPressFired = false
        if let last = state.lastTapReleasedAt, time - last < config.doublePressInterval {
            state.isSecondTap = true
            state.pendingPressDeadline = nil      // the deferred single press becomes a double press
            state.pendingPressReleasedAt = nil
        } else {
            state.isSecondTap = false
        }
        states[button] = state
    }

    private mutating func release(_ button: RemoteButton, at time: TimeInterval) -> [ButtonEvent] {
        guard var state = states[button], state.pressedAt != nil else { return [] }
        defer { states[button] = state }
        state.pressedAt = nil
        if state.longPressFired {
            state.longPressFired = false
            state.isSecondTap = false
            state.lastTapReleasedAt = nil
            return [ButtonEvent(button: button, gesture: .longPress, phase: .ended, time: time)]
        }
        if state.isSecondTap {
            state.isSecondTap = false
            state.lastTapReleasedAt = nil
            return [ButtonEvent(button: button, gesture: .doublePress, time: time)]
        }
        state.lastTapReleasedAt = time
        if config.deferredPressButtons.contains(button) {
            state.pendingPressDeadline = time + config.doublePressInterval
            state.pendingPressReleasedAt = time
            return []
        }
        return [ButtonEvent(button: button, gesture: .press, time: time)]
    }
}
