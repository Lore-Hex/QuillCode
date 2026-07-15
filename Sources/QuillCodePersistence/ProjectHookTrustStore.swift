import Foundation
import QuillCodeCore

public struct ProjectHookTrustRecord: Codable, Sendable, Hashable {
    public var hookID: String
    public var definitionHash: String
    public var decision: ProjectHookTrustDecision
    public var updatedAt: Date

    public init(
        hookID: String,
        definitionHash: String,
        decision: ProjectHookTrustDecision,
        updatedAt: Date = Date()
    ) {
        self.hookID = hookID
        self.definitionHash = definitionHash
        self.decision = decision
        self.updatedAt = updatedAt
    }
}

public struct ProjectHookTrustLoadResult: Sendable, Hashable {
    public var records: [ProjectHookTrustRecord]
    public var degraded: Bool
    public var diagnostics: [String]

    public init(
        records: [ProjectHookTrustRecord] = [],
        degraded: Bool = false,
        diagnostics: [String] = []
    ) {
        self.records = records
        self.degraded = degraded
        self.diagnostics = diagnostics
    }

    public func status(for hook: ProjectPluginHook) -> ProjectHookTrustStatus {
        if hook.isManaged { return .trusted }
        guard !degraded,
              let record = records.last(where: { $0.hookID == hook.id }),
              record.definitionHash == hook.definitionHash
        else { return .reviewRequired }
        switch record.decision {
        case .trusted: return .trusted
        case .disabled: return .disabled
        }
    }
}

public enum ProjectHookTrustStoreError: LocalizedError, Sendable, Equatable {
    case degradedFile
    case managedHook

    public var errorDescription: String? {
        switch self {
        case .degradedFile:
            return "The hook trust file is unreadable or uses an unsupported format. It was left unchanged."
        case .managedHook:
            return "Managed hooks are trusted by policy and cannot be changed here."
        }
    }
}

/// Atomic, scoped persistence for reviewed hooks. The scope root is either a workspace root or the
/// app home for user-level definitions.
///
/// A corrupt or newer file fails closed: every discovered hook returns to `reviewRequired` until
/// the trust file is repaired. Trust is valid only for the exact definition hash.
public struct ProjectHookTrustFileStore: Sendable {
    public static let currentVersion = 1
    public static let maxRecords = 256

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileURL(forWorkspaceRoot root: URL) -> URL {
        WorkspaceScopedStoreFileLocator.fileURL(directory: directory, workspaceRoot: root)
    }

    public func load(forWorkspaceRoot root: URL) -> ProjectHookTrustLoadResult {
        let fileURL = fileURL(forWorkspaceRoot: root)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(WirePayload.self, from: Data(contentsOf: fileURL))
            guard payload.version == Self.currentVersion else {
                return .init(
                    degraded: true,
                    diagnostics: ["Hook trust file uses an unsupported format; all hooks require review."]
                )
            }
            return .init(records: Self.normalized(payload.records))
        } catch {
            return .init(
                degraded: true,
                diagnostics: ["Hook trust file is unreadable; all hooks require review."]
            )
        }
    }

    public func setDecision(
        _ decision: ProjectHookTrustDecision,
        for hook: ProjectPluginHook,
        workspaceRoot: URL,
        now: Date = Date()
    ) throws {
        guard !hook.isManaged else {
            throw ProjectHookTrustStoreError.managedHook
        }
        let existing = load(forWorkspaceRoot: workspaceRoot)
        guard !existing.degraded else {
            throw ProjectHookTrustStoreError.degradedFile
        }
        var records = existing.records
        records.removeAll { $0.hookID == hook.id }
        records.append(ProjectHookTrustRecord(
            hookID: hook.id,
            definitionHash: hook.definitionHash,
            decision: decision,
            updatedAt: now
        ))
        try save(records, forWorkspaceRoot: workspaceRoot)
    }

    public func save(_ records: [ProjectHookTrustRecord], forWorkspaceRoot root: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = WirePayload(version: Self.currentVersion, records: Self.normalized(records))
        try encoder.encode(payload).write(to: fileURL(forWorkspaceRoot: root), options: .atomic)
    }

    private struct WirePayload: Codable {
        var version: Int
        var records: [ProjectHookTrustRecord]
    }

    private static func normalized(_ records: [ProjectHookTrustRecord]) -> [ProjectHookTrustRecord] {
        var latestByID: [String: ProjectHookTrustRecord] = [:]
        for record in records where isValid(record) {
            if let existing = latestByID[record.hookID], existing.updatedAt > record.updatedAt {
                continue
            }
            latestByID[record.hookID] = record
        }
        return latestByID.values
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                return lhs.hookID < rhs.hookID
            }
            .suffix(maxRecords)
            .map { $0 }
    }

    private static func isValid(_ record: ProjectHookTrustRecord) -> Bool {
        !record.hookID.isEmpty
            && record.hookID.count <= 512
            && record.definitionHash.count == 64
            && record.definitionHash.allSatisfy { $0.isHexDigit }
    }
}
