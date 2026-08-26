import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Names of the user's Shortcuts, from `shortcuts list`. Loaded off the main thread on demand.
@MainActor
@Observable
final class ShortcutsCatalog {
    private(set) var names: [String] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            let result = Self.listShortcuts()
            await MainActor.run {
                switch result {
                case .success(let names): self.names = names
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    nonisolated private static func listShortcuts() -> Result<[String], Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let names = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return .success(names)
    }
}

/// An application the user can bind: identity for launching plus a name for display.
struct AppChoice: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    init?(url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        self.bundleID = bundleID
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        self.name = name
    }

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Ordinary (Dock-visible) apps currently running, excluding ourselves.
    static func runningApps() -> [AppChoice] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return AppChoice(bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Open-panel chooser rooted in /Applications.
    static func choose(completion: @escaping (AppChoice?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            completion(AppChoice(url: url))
        }
    }
}
