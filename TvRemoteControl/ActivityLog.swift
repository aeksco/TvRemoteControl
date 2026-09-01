import Foundation
import Observation
import RemoteCore

/// A bounded, in-memory record of what the remotes did: gestures, the actions they fired, connection
/// changes and the raw HID reports. The panel shows live state; this is the history behind it, read by
/// the Activity Log window. Nothing is persisted — it exists to answer "what did that button just do?".
@MainActor
@Observable
final class ActivityLog {
    struct Entry: Identifiable, Equatable {
        enum Kind: String {
            case device, gesture, action, report

            var label: String {
                switch self {
                case .device: "DEVICE"
                case .gesture: "GESTURE"
                case .action: "ACTION"
                case .report: "REPORT"
                }
            }
        }

        let id = UUID()
        let at: Date
        let kind: Kind
        let remoteID: String?
        let title: String
        let detail: String?
        let isError: Bool
    }

    /// Newest first.
    private(set) var entries: [Entry] = []

    /// Raw reports arrive far faster than anything else (a touch drag is dozens a second), so they get
    /// their own smaller budget: a burst of them can never push the gesture history out of the log.
    static let limit = 400
    static let reportLimit = 120

    private var reportCount = 0

    func log(_ kind: Entry.Kind, remoteID: String? = nil, _ title: String, detail: String? = nil, isError: Bool = false) {
        entries.insert(Entry(at: .now, kind: kind, remoteID: remoteID, title: title, detail: detail, isError: isError), at: 0)
        if kind == .report {
            reportCount += 1
            if reportCount > Self.reportLimit, let oldest = entries.lastIndex(where: { $0.kind == .report }) {
                entries.remove(at: oldest)
                reportCount -= 1
            }
        }
        if entries.count > Self.limit {
            let removed = entries.suffix(from: Self.limit)
            reportCount -= removed.filter { $0.kind == .report }.count
            entries.removeLast(entries.count - Self.limit)
        }
    }

    func clear() {
        entries.removeAll()
        reportCount = 0
    }
}
