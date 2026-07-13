import Foundation

struct WorkspaceSubagentSessionRecord: Codable, Sendable, Hashable {
    var parentThreadID: UUID
    var state: WorkspaceSubagentRunState
    var createdAt: Date
    var updatedAt: Date

    init(
        parentThreadID: UUID,
        state: WorkspaceSubagentRunState,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.parentThreadID = parentThreadID
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkspaceSubagentSessionStore: Sendable {
    let directory: URL

    func save(_ record: WorkspaceSubagentSessionRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = try fileURL(for: record.state.id)
        try encoder.encode(record).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    func load(_ runID: String) throws -> WorkspaceSubagentSessionRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            WorkspaceSubagentSessionRecord.self,
            from: Data(contentsOf: try fileURL(for: runID))
        )
    }

    func delete(_ runID: String) throws {
        let url = try fileURL(for: runID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for runID: String) throws -> URL {
        guard let id = UUID(uuidString: runID) else {
            throw WorkspaceSubagentSessionStoreError.invalidRunID
        }
        return directory.appendingPathComponent("\(id.uuidString).json")
    }
}

private enum WorkspaceSubagentSessionStoreError: Error {
    case invalidRunID
}
