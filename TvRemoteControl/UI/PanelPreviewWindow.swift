import AppKit
import SwiftUI

/// Development convenience: `open TvRemoteControl.app --args --preview-panel` renders the menu-bar panel
/// in an ordinary window, so its layout can be iterated on (and screenshotted) without holding the
/// popover open. Never shown in normal use.
@MainActor
enum PanelPreviewWindow {
    private static var window: NSWindow?

    static func show(monitor: HIDRemoteMonitor) {
        if window == nil {
            let hosting = NSHostingController(rootView: MenuBarView(monitor: monitor))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Panel Preview"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}
