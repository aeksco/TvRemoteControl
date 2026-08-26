import AppKit
import Foundation
import os

/// Keeps "hold until release" actions pressed: key down when the long press begins, auto-repeat at the
/// system's key-repeat cadence, key up when the button is released — or when anything else could leave
/// the key stranded (remote gone, app disabled, rebinding, quit).
@MainActor
final class HoldController {
    private struct ActiveHold {
        let action: any HoldableAction
        let repeater: Task<Void, Never>?
    }

    private var active: [String: ActiveHold] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TvRemoteControl", category: "hold")

    static func key(remoteID: String, button: String) -> String {
        "\(remoteID)/\(button)"
    }

    func isHolding(_ key: String) -> Bool {
        active[key] != nil
    }

    func begin(key: String, action: any HoldableAction) throws {
        end(key: key)
        try action.keyDown(isRepeat: false)
        let delay = NSEvent.keyRepeatDelay
        let interval = NSEvent.keyRepeatInterval
        var repeater: Task<Void, Never>?
        if interval > 0 {
            repeater = Task {
                try? await Task.sleep(for: .seconds(max(delay, 0.05)))
                while !Task.isCancelled {
                    try? action.keyDown(isRepeat: true)
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
        }
        active[key] = ActiveHold(action: action, repeater: repeater)
    }

    func end(key: String) {
        guard let hold = active.removeValue(forKey: key) else { return }
        hold.repeater?.cancel()
        do {
            try hold.action.keyUp()
        } catch {
            logger.error("keyUp failed for \(hold.action.displayString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Release every hold, or only those whose key starts with `prefix` (a remote ID).
    func endAll(prefix: String? = nil) {
        for key in active.keys where prefix.map({ key.hasPrefix($0) }) ?? true {
            end(key: key)
        }
    }
}
