import SwiftUI

struct SettingsSection: View {
    @Bindable var settings: AppSettings
    let seizedDeviceCount: Int

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enabled", isOn: $settings.isEnabled)
                    .help("Global switch: when off, buttons are not decoded and macOS keeps full control of the remote.")

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Exclusive mode", isOn: $settings.exclusiveMode)
                        .disabled(!settings.isEnabled)
                    Text(exclusiveExplanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("Long press")
                    Spacer()
                    Stepper("\(settings.longPressMilliseconds) ms", value: $settings.longPressMilliseconds, in: 200...2000, step: 50)
                }
                HStack {
                    Text("Double press")
                    Spacer()
                    Stepper("\(settings.doublePressMilliseconds) ms", value: $settings.doublePressMilliseconds, in: 100...1000, step: 25)
                }
            }
            .font(.caption)
            .controlSize(.small)
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text("Settings")
                if !settings.isEnabled {
                    Tag(text: "Disabled", color: .secondary)
                } else if seizedDeviceCount > 0 {
                    Tag(text: "Exclusive", color: .orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var exclusiveExplanation: String {
        if settings.exclusiveMode {
            return seizedDeviceCount > 0
                ? "The remote is seized: macOS no longer changes the volume or play state itself. Nothing is bound yet, so those buttons currently do nothing."
                : "Will seize the remote as soon as one connects."
        }
        return "Seize the remote so macOS stops reacting to Volume, Mute and Play/Pause itself. Leave off until bindings exist, or those buttons go dead."
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}
