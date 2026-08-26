import RemoteCore
import SwiftUI

/// One remote: identity, connection dot, battery, and a flash on every input report so the user
/// can tell which physical remote is which.
struct RemoteRow: View {
    let remote: RemoteDevice
    let now: Date

    @State private var isFlashing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: remote.generation.symbolName)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(remote.isConnected ? Color.primary : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(remote.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(remote.generation.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(identityLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(activityLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !remote.heldButtons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(remote.heldButtons.buttons, id: \.self) { button in
                            Label(button.displayName, systemImage: button.symbolName)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                        }
                    }
                }
                ForEach(Array(remote.recentEvents.enumerated()), id: \.offset) { index, event in
                    Label("\(event.button.displayName) · \(event.gesture.displayName)", systemImage: event.button.symbolName)
                        .font(.caption2)
                        .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                if let feedback = remote.lastAction {
                    Label(feedbackText(feedback), systemImage: feedback.error == nil ? "arrow.turn.down.right" : "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(feedback.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .lineLimit(2)
                }
                if remote.isConnected, !remote.hasProfile {
                    Text("No verified button layout for this generation yet — showing raw reports only.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let report = remote.lastReport {
                    Text("\(report.sourceLabel) · id \(report.reportID): \(report.hex)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                if let error = remote.openError {
                    Label("Can't read input — \(error)", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                ConnectionDot(isConnected: remote.isConnected)
                if remote.isSeized {
                    Tag(text: "Exclusive", color: .orange)
                }
                if remote.isConnected, let battery = remote.batteryPercent {
                    Label("\(battery)%", systemImage: batterySymbol(for: battery))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isFlashing ? Color.accentColor.opacity(0.28) : Color.clear)
        )
        .onChange(of: remote.lastInputAt) {
            flash()
        }
    }

    private func feedbackText(_ feedback: ActionFeedback) -> String {
        var text = "\(feedback.button.displayName) \(feedback.gesture.displayName.lowercased()) → \(feedback.summary)"
        if let error = feedback.error { text += " — \(error)" }
        return text
    }

    private var identityLine: String {
        var parts: [String] = []
        if let serial = remote.serialNumber, !serial.isEmpty { parts.append("S/N \(serial)") }
        parts.append("PID \(remote.productIDHex)")
        parts.append("\(remote.bindings.count) binding\(remote.bindings.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private var activityLine: String {
        if remote.isConnected {
            if let last = remote.lastInputAt {
                return "Connected · last input \(relative(last)) · \(remote.inputCount) reports · \(remote.eventCount) gestures"
            }
            return "Connected · no input yet — press any button"
        }
        return "Disconnected · last seen \(relative(remote.lastSeenAt))"
    }

    private func relative(_ date: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded(.down))
        switch seconds {
        case ..<1: return "just now"
        case ..<60: return "\(seconds) s ago"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86400: return "\(seconds / 3600) h ago"
        default: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func batterySymbol(for percent: Int) -> String {
        switch percent {
        case ..<10: "battery.0percent"
        case ..<35: "battery.25percent"
        case ..<60: "battery.50percent"
        case ..<85: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private func flash() {
        isFlashing = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.45)) { isFlashing = false }
        }
    }
}

struct ConnectionDot: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(isConnected ? "Connected" : "Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
