import Foundation
import RemoteCore

/// Runs one `GestureRecognizer` against the wall clock: feeds it masks as reports arrive and schedules
/// a timer for `nextDeadline()` so long presses and deferred single presses fire while the remote is quiet.
@MainActor
final class GestureDriver {
    private var recognizer: GestureRecognizer
    private var timer: Task<Void, Never>?
    private let onEvents: ([ButtonEvent]) -> Void

    init(config: GestureConfig, onEvents: @escaping ([ButtonEvent]) -> Void) {
        recognizer = GestureRecognizer(config: config)
        self.onEvents = onEvents
    }

    var config: GestureConfig {
        get { recognizer.config }
        set {
            recognizer.config = newValue
            reschedule()
        }
    }

    var held: ButtonMask { recognizer.held }

    func handle(mask: ButtonMask) {
        emit(recognizer.handle(mask: mask, at: Self.now()))
        reschedule()
    }

    /// Forget everything in flight (remote disconnected, app disabled).
    func reset() {
        timer?.cancel()
        timer = nil
        recognizer = GestureRecognizer(config: recognizer.config)
    }

    /// Monotonic seconds — immune to wall-clock adjustments.
    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func emit(_ events: [ButtonEvent]) {
        guard !events.isEmpty else { return }
        onEvents(events)
    }

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard let deadline = recognizer.nextDeadline() else { return }
        let delay = max(0, deadline - Self.now())
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.emit(self.recognizer.tick(at: Self.now()))
            self.reschedule()
        }
    }
}
