import Foundation
import QuillCodeCore

public struct ExternalAgentConfigImportHistoryStore: Sendable {
    public static let maximumEntries = 100
    public static let maximumBytes = 4 * 1_024 * 1_024

    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [ExternalAgentConfigImportHistory] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= Self.maximumBytes
        else {
            throw ExternalAgentConfigImportHistoryStoreError.invalidHistoryFile
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count <= Self.maximumBytes else {
            throw ExternalAgentConfigImportHistoryStoreError.exceedsMaximumBytes
        }
        let histories = try JSONDecoder().decode(
            [ExternalAgentConfigImportHistory].self,
            from: data
        )
        return Array(histories.sorted { $0.completedAtMs > $1.completedAtMs }.prefix(Self.maximumEntries))
    }

    public func record(_ history: ExternalAgentConfigImportHistory) throws {
        var histories = try load().filter { $0.importId != history.importId }
        histories.insert(history, at: 0)
        histories = Array(histories.prefix(Self.maximumEntries))

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try PrivateDirectory.ensureExists(at: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(histories)
        guard data.count <= Self.maximumBytes else {
            throw ExternalAgentConfigImportHistoryStoreError.exceedsMaximumBytes
        }
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

public enum ExternalAgentConfigImportHistoryStoreError: Error, Sendable, Equatable {
    case invalidHistoryFile
    case exceedsMaximumBytes
}
