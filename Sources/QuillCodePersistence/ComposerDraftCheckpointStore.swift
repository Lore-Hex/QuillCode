import Foundation

public struct ComposerDraftCheckpoint: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var threadID: UUID?
    public var draft: String?

    public init(threadID: UUID?, draft: String?) {
        self.schemaVersion = Self.currentSchemaVersion
        self.threadID = threadID
        self.draft = Self.normalized(draft)
    }

    fileprivate var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && draft.map { $0.utf8.count <= ComposerDraftCheckpointStore.maximumDraftBytes } != false
    }

    private static func normalized(_ draft: String?) -> String? {
        guard let draft,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return draft
    }
}

public enum ComposerDraftCheckpointStoreError: LocalizedError, Equatable, Sendable {
    case draftExceedsSizeLimit(maximumBytes: Int)
    case recordExceedsSizeLimit(maximumBytes: Int)
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .draftExceedsSizeLimit(let maximumBytes):
            "The composer draft exceeds the \(maximumBytes)-byte checkpoint limit."
        case .recordExceedsSizeLimit(let maximumBytes):
            "The composer draft checkpoint exceeds the \(maximumBytes)-byte storage limit."
        case .invalidRecord:
            "The composer draft checkpoint is invalid."
        }
    }
}

/// Stores only the current unsent text, separately from the potentially large thread transcript.
/// Per-owner files keep a typing checkpoint bounded and make one chat's draft independent of every
/// other chat. A nil draft is a durable tombstone so older thread snapshots cannot resurrect text.
public struct ComposerDraftCheckpointStore: Sendable {
    public static let maximumDraftBytes = 1 * 1_024 * 1_024
    public static let maximumRecordBytes = maximumDraftBytes * 6 + 4_096
    private static let filePermissions = 0o600

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public func save(_ draft: String?, for threadID: UUID?) throws {
        let checkpoint = ComposerDraftCheckpoint(threadID: threadID, draft: draft)
        guard checkpoint.draft.map({ $0.utf8.count <= Self.maximumDraftBytes }) != false else {
            throw ComposerDraftCheckpointStoreError.draftExceedsSizeLimit(
                maximumBytes: Self.maximumDraftBytes
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(checkpoint)
        guard data.count <= Self.maximumRecordBytes else {
            throw ComposerDraftCheckpointStoreError.recordExceedsSizeLimit(
                maximumBytes: Self.maximumRecordBytes
            )
        }

        try PrivateDirectory.ensureExists(at: directory)
        let destination = fileURL(for: threadID)
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: destination.path
        )
    }

    public func load(for threadID: UUID?) throws -> ComposerDraftCheckpoint? {
        guard let data = try BoundedFileDataReader.readIfPresent(
            from: fileURL(for: threadID),
            maximumBytes: Self.maximumRecordBytes
        ) else {
            return nil
        }
        let checkpoint = try JSONDecoder().decode(ComposerDraftCheckpoint.self, from: data)
        guard checkpoint.isValid, checkpoint.threadID == threadID else {
            throw ComposerDraftCheckpointStoreError.invalidRecord
        }
        return checkpoint
    }

    public func delete(for threadID: UUID?) throws {
        let destination = fileURL(for: threadID)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    private func fileURL(for threadID: UUID?) -> URL {
        let name = threadID.map { "thread-\($0.uuidString.lowercased())" } ?? "pending"
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
