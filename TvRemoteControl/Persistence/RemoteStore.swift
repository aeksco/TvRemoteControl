import Foundation
import RemoteCore
import os

/// On-disk record of a remote. Bindings will hang off this same record in Phase 3.
nonisolated struct RemoteRecord: Codable, Equatable {
    var id: String
    var name: String
    var generation: RemoteGeneration
    var vendorID: Int
    var productID: Int
    var serialNumber: String?
    var transport: String
    var firstSeenAt: Date
    var lastSeenAt: Date
    /// Added in schema 2. Nil when loading a schema-1 file; the device then gets the defaults.
    var bindings: BindingSet?
}

nonisolated struct RemoteStoreFile: Codable {
    static let currentSchemaVersion = 2
    var schemaVersion = RemoteStoreFile.currentSchemaVersion
    var remotes: [RemoteRecord] = []
}

/// JSON in ~/Library/Application Support/<bundle id>/remotes.json, keyed by remote serial.
nonisolated struct RemoteStore {
    let fileURL: URL
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TvRemoteControl", category: "store")

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let folder = support.appending(path: Bundle.main.bundleIdentifier ?? "TvRemoteControl", directoryHint: .isDirectory)
            self.fileURL = folder.appending(path: "remotes.json")
        }
    }

    func load() -> [RemoteRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(RemoteStoreFile.self, from: data)
            guard (1...RemoteStoreFile.currentSchemaVersion).contains(file.schemaVersion) else {
                logger.warning("remotes.json schema \(file.schemaVersion) ≠ \(RemoteStoreFile.currentSchemaVersion); ignoring")
                return []
            }
            return file.remotes
        } catch {
            logger.error("Failed to read \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ remotes: [RemoteRecord]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(RemoteStoreFile(remotes: remotes))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to write \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension RemoteRecord {
    init(remote: RemoteDevice) {
        id = remote.id
        name = remote.name
        generation = remote.generation
        vendorID = remote.vendorID
        productID = remote.productID
        serialNumber = remote.serialNumber
        transport = remote.transport
        firstSeenAt = remote.firstSeenAt
        lastSeenAt = remote.lastSeenAt
        bindings = remote.bindings
    }
}

extension RemoteDevice {
    init(record: RemoteRecord) {
        id = record.id
        name = record.name
        generation = record.generation
        vendorID = record.vendorID
        productID = record.productID
        serialNumber = record.serialNumber
        transport = record.transport
        registryEntryID = nil
        isPersistent = true
        firstSeenAt = record.firstSeenAt
        lastSeenAt = record.lastSeenAt
        bindings = record.bindings ?? BindingSet.defaults(for: RemoteProfiles.profile(for: record.generation)?.buttons ?? [])
    }
}
