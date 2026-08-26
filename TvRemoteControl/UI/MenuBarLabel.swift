import SwiftUI

/// The status-item icon: filled while at least one remote is connected.
struct MenuBarLabel: View {
    var monitor: HIDRemoteMonitor

    var body: some View {
        Image(systemName: monitor.hasConnectedRemote ? "appletvremote.gen4.fill" : "appletvremote.gen4")
            .accessibilityLabel(monitor.hasConnectedRemote ? "Siri Remote connected" : "No Siri Remote connected")
    }
}
