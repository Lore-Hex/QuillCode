import Foundation
import QuillCodeCore

/// Stores raw held tool calls separately from ordinary thread JSON. The containing directory and
/// every payload are restricted to the owning user; UUID keys keep filenames path-safe.
public struct SubagentApprovalPayloadStore: Sendable {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ call: ToolCall, key: UUID) throws {
        try prepareDirectory()
        let url = fileURL(for: key)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(call).write(to: url, options: .atomic)
        try protectFile(url)
    }

    public func load(_ key: UUID) throws -> ToolCall {
        try prepareDirectory()
        let url = fileURL(for: key)
        try protectFile(url)
        return try JSONDecoder().decode(ToolCall.self, from: Data(contentsOf: url))
    }

    public func delete(_ key: UUID) throws {
        try prepareDirectory()
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for key: UUID) -> URL {
        directory.appendingPathComponent("\(key.uuidString).json")
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    private func protectFile(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: url.path
        )
    }
}
