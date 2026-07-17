import Foundation
import QuillCodeCore

public struct ExternalAgentConfigImportedSession: Sendable {
    public var thread: ChatThread
    public var cwd: URL?
    public var sourcePath: String

    public init(thread: ChatThread, cwd: URL?, sourcePath: String) {
        self.thread = thread
        self.cwd = cwd
        self.sourcePath = sourcePath
    }
}

public actor ClaudeCodeExternalAgentConfigService {
    public typealias SessionImporter = @Sendable (ExternalAgentConfigImportedSession) async throws -> UUID

    public let sourceHomeDirectory: URL
    public let destinationPaths: QuillCodePaths
    private let appConfig: AppConfig
    private let historyStore: ExternalAgentConfigImportHistoryStore
    private var importIsActive = false
    private var importWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        sourceHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        destinationPaths: QuillCodePaths = QuillCodePaths(),
        appConfig: AppConfig
    ) {
        self.sourceHomeDirectory = sourceHomeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.destinationPaths = destinationPaths
        self.appConfig = appConfig
        self.historyStore = ExternalAgentConfigImportHistoryStore(
            fileURL: destinationPaths.externalAgentConfigImportHistoryFile
        )
    }

    public func detect(
        cwds: [URL] = [],
        includeHome: Bool = false,
        now: Date = Date()
    ) throws -> [ExternalAgentConfigMigrationItem] {
        try catalog(cwds: cwds, includeHome: includeHome, now: now).items
    }

    public func importItem(
        _ requested: ExternalAgentConfigMigrationItem,
        now: Date = Date(),
        importSession: @escaping SessionImporter
    ) async -> ExternalAgentConfigImportTypeResult {
        await acquireImportPermit()
        defer { releaseImportPermit() }
        guard !Task.isCancelled else {
            return invalidResult(requested, message: "The migration was cancelled before it started.")
        }
        do {
            let includeHome = requested.cwd?.isEmpty != false
            let cwds = requested.cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }.map { [$0] } ?? []
            let current = try catalog(cwds: cwds, includeHome: includeHome, now: now)
            guard let entry = current.matching(requested) else {
                return invalidResult(
                    requested,
                    message: "The migration item is no longer available or does not match current Claude Code data."
                )
            }
            return await ClaudeCodeExternalAgentConfigMaterializer.run(
                entry: entry,
                requested: requested,
                destinationPaths: destinationPaths,
                appConfig: appConfig,
                importSession: importSession
            )
        } catch {
            return invalidResult(requested, message: String(describing: error))
        }
    }

    public func histories() throws -> [ExternalAgentConfigImportHistory] {
        try historyStore.load()
    }

    public func record(_ history: ExternalAgentConfigImportHistory) throws {
        try historyStore.record(history)
    }
}

private extension ClaudeCodeExternalAgentConfigService {
    func catalog(
        cwds: [URL],
        includeHome: Bool,
        now: Date
    ) throws -> ClaudeCodeExternalAgentConfigCatalog {
        let importedSessions: Set<String> = Set(try historyStore.load().flatMap(\.successes).compactMap {
            guard $0.itemType == .sessions, let source = $0.source else { return nil }
            return URL(fileURLWithPath: source).standardizedFileURL.resolvingSymlinksInPath().path
        })
        return try ClaudeCodeExternalAgentConfigCatalogBuilder.build(
            sourceHomeDirectory: sourceHomeDirectory,
            destinationPaths: destinationPaths,
            cwds: cwds,
            includeHome: includeHome,
            importedSessionPaths: importedSessions,
            now: now
        )
    }

    func invalidResult(
        _ item: ExternalAgentConfigMigrationItem,
        message: String
    ) -> ExternalAgentConfigImportTypeResult {
        .init(itemType: item.itemType, failures: [.init(
            itemType: item.itemType,
            cwd: item.cwd,
            errorType: "migration_item_not_detected",
            failureStage: "detection_validation",
            message: message
        )])
    }

    func acquireImportPermit() async {
        if !importIsActive {
            importIsActive = true
            return
        }
        await withCheckedContinuation { continuation in
            importWaiters.append(continuation)
        }
    }

    func releaseImportPermit() {
        guard !importWaiters.isEmpty else {
            importIsActive = false
            return
        }
        importWaiters.removeFirst().resume()
    }
}
