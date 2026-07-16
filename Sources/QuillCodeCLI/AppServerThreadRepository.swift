import Foundation
import QuillCodeCore
import QuillCodePersistence

struct AppServerThreadSettings: Codable, Sendable, Equatable {
    var cwd: URL
    var ephemeral: Bool
    var approvalPolicy: CLIJSONValue
    var approvalsReviewer: String
    var sandbox: CLISandboxMode
    var sessionID: UUID?
    var forkedFromID: UUID?
    var runtimeAppConfig: AppConfig?
    var compactPrompt: String?
    var name: String?
    var gitInfo: AppServerThreadGitInfo?
    var reasoningEffort: String?
    var reasoningSummary: String?
    var serviceTier: String?
    var collaborationMode: AppServerCollaborationMode?
    var memoryMode: AppServerThreadMemoryMode?
    var sandboxPolicy: AppServerSandboxPolicy?
    var permissionProfileID: String?
    var permissionProfileIsExplicit: Bool?

    init(
        cwd: URL,
        ephemeral: Bool = false,
        approvalPolicy: CLIJSONValue = .string("on-request"),
        approvalsReviewer: String = "user",
        sandbox: CLISandboxMode = .readOnly,
        sessionID: UUID? = nil,
        forkedFromID: UUID? = nil,
        runtimeAppConfig: AppConfig? = nil,
        compactPrompt: String? = nil,
        name: String? = nil,
        gitInfo: AppServerThreadGitInfo? = nil,
        reasoningEffort: String? = nil,
        reasoningSummary: String? = nil,
        serviceTier: String? = nil,
        collaborationMode: AppServerCollaborationMode? = nil,
        memoryMode: AppServerThreadMemoryMode? = nil,
        sandboxPolicy: AppServerSandboxPolicy? = nil,
        permissionProfileID: String? = nil,
        permissionProfileIsExplicit: Bool? = nil
    ) {
        self.cwd = cwd.standardizedFileURL
        self.ephemeral = ephemeral
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandbox = sandbox
        self.sessionID = sessionID
        self.forkedFromID = forkedFromID
        self.runtimeAppConfig = runtimeAppConfig
        self.compactPrompt = compactPrompt
        self.name = name
        self.gitInfo = gitInfo
        self.reasoningEffort = reasoningEffort
        self.reasoningSummary = reasoningSummary
        self.serviceTier = serviceTier
        self.collaborationMode = collaborationMode
        self.memoryMode = memoryMode
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfileID = permissionProfileID
        self.permissionProfileIsExplicit = permissionProfileIsExplicit
    }

    var effectiveMemoryMode: AppServerThreadMemoryMode {
        memoryMode ?? .enabled
    }

    var effectiveSandboxPolicy: AppServerSandboxPolicy {
        sandboxPolicy ?? AppServerSandboxPolicy(mode: sandbox)
    }
}

struct AppServerThreadRecord: Sendable, Equatable {
    var thread: ChatThread
    var settings: AppServerThreadSettings
}

actor AppServerThreadRepository {
    private let threadStore: JSONThreadStore
    private let metadataStore: AppServerThreadMetadataStore
    private let fallbackCWD: URL
    private var ephemeral: [UUID: AppServerThreadRecord] = [:]

    init(paths: QuillCodePaths, fallbackCWD: URL) {
        self.threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        self.metadataStore = AppServerThreadMetadataStore(directory: paths.appServerMetadataDirectory)
        self.fallbackCWD = fallbackCWD.standardizedFileURL
    }

    func create(_ record: AppServerThreadRecord) throws {
        if record.settings.ephemeral {
            ephemeral[record.thread.id] = record
        } else {
            try threadStore.save(record.thread)
            try metadataStore.save(record.settings, for: record.thread.id)
        }
    }

    func save(_ record: AppServerThreadRecord) throws {
        try create(record)
    }

    /// Saves a history-only mutation without rewriting unchanged app-server metadata. This keeps
    /// rollback to one atomic thread-file replacement and avoids a partial two-file transaction.
    func saveThread(_ thread: ChatThread) throws {
        if var record = ephemeral[thread.id] {
            record.thread = thread
            ephemeral[thread.id] = record
        } else {
            try threadStore.save(thread)
        }
    }

    func load(_ id: UUID) throws -> AppServerThreadRecord {
        if let record = ephemeral[id] { return record }
        let thread = try threadStore.load(id)
        let settings = metadataStore.load(id) ?? inferredSettings(for: thread)
        return AppServerThreadRecord(thread: thread, settings: settings)
    }

    func list() -> [AppServerThreadRecord] {
        var records = threadStore.listing().threads.map { thread in
            AppServerThreadRecord(
                thread: thread,
                settings: metadataStore.load(thread.id) ?? inferredSettings(for: thread)
            )
        }
        let persistedIDs = Set(records.map(\.thread.id))
        records.append(contentsOf: ephemeral.values.filter { !persistedIDs.contains($0.thread.id) })
        return records.sorted { $0.thread.updatedAt > $1.thread.updatedAt }
    }

    func delete(_ id: UUID) throws {
        ephemeral[id] = nil
        try threadStore.delete(id)
        try metadataStore.delete(id)
    }

    private func inferredSettings(for thread: ChatThread) -> AppServerThreadSettings {
        AppServerThreadSettings(
            cwd: fallbackCWD,
            approvalPolicy: .string(thread.mode == .readOnly ? "never" : "on-request"),
            approvalsReviewer: thread.mode == .auto ? "auto_review" : "user",
            sandbox: thread.mode == .readOnly ? .readOnly : .workspaceWrite,
            forkedFromID: thread.forkParentThreadID
        )
    }
}

private struct AppServerThreadMetadataStore: Sendable {
    let directory: URL

    func save(_ settings: AppServerThreadSettings, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL(for: id), options: .atomic)
    }

    func load(_ id: UUID) -> AppServerThreadSettings? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(AppServerThreadSettings.self, from: data)
    }

    func delete(_ id: UUID) throws {
        let file = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
