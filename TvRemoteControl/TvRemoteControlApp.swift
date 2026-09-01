import AppKit
import SwiftUI

@main
struct TvRemoteControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: appDelegate.monitor)
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let monitor: HIDRemoteMonitor

    override init() {
        settings = AppSettings()
        monitor = HIDRemoteMonitor(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start()
        // Development convenience: `open TvRemoteControl.app --args --preview-panel`.
        if CommandLine.arguments.contains("--preview-panel") {
            PanelPreviewWindow.show(monitor: monitor)
        }
    }

    /// Menu-bar app: closing a window (the dev panel preview) must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Permissions can change underneath us in System Settings; re-check every time we come to the front.
    func applicationDidBecomeActive(_ notification: Notification) {
        monitor.refreshPermission()
    }

    /// Release seized devices and any held keys before the process goes away.
    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
