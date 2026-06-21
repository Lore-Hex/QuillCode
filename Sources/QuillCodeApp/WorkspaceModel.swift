import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

public enum ToolCardStatus: String, Codable, Sendable, Hashable {
    case queued
    case running
    case done
    case failed
    case review
}

public enum ToolArtifactKind: String, Codable, Sendable, Hashable {
    case file
    case url
    case path
}

public struct ToolArtifactState: Codable, Sendable, Hashable, Identifiable {
    public var id: String { value }
    public var value: String
    public var label: String
    public var kind: ToolArtifactKind
    public var detail: String { Self.detail(for: value, kind: kind) }
    public var href: String? { Self.href(for: value, kind: kind) }
    public var isImagePreview: Bool { Self.isImagePreview(for: value, kind: kind) }
    public var previewURL: String? { Self.previewURL(for: value, kind: kind) }

    public init(value: String) {
        self.value = value
        self.label = Self.label(for: value)
        self.kind = Self.kind(for: value)
    }

    private static func kind(for value: String) -> ToolArtifactKind {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return value.hasPrefix("/") ? .file : .path
        }
        if scheme == "http" || scheme == "https" {
            return .url
        }
        if isInlineImageData(value) {
            return .url
        }
        if scheme == "file" {
            return .file
        }
        return .path
    }

    private static func label(for value: String) -> String {
        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "data"].contains(scheme) {
            if scheme == "data" {
                return isInlineImageData(value) ? "Inline image" : value
            }
            if scheme == "http" || scheme == "https" {
                let host = url.host ?? value
                return url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
            }
            if !url.lastPathComponent.isEmpty {
                return url.lastPathComponent
            }
            return value
        }
        let url = URL(fileURLWithPath: value)
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? value : lastPathComponent
    }

    private static func detail(for value: String, kind: ToolArtifactKind) -> String {
        switch kind {
        case .url:
            if isInlineImageData(value) {
                return "Image artifact"
            }
            guard let url = URL(string: value), let host = url.host else { return value }
            return url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
        case .file:
            let url = value.hasPrefix("file://")
                ? URL(string: value)
                : URL(fileURLWithPath: value)
            guard let path = url?.deletingLastPathComponent().path, !path.isEmpty else {
                return "File artifact"
            }
            return path
        case .path:
            return value
        }
    }

    private static func isImagePreview(for value: String, kind: ToolArtifactKind) -> Bool {
        if isInlineImageData(value) {
            return true
        }
        guard kind == .file || kind == .url else {
            return false
        }
        let pathExtension: String
        if let url = URL(string: value), url.scheme != nil {
            pathExtension = url.pathExtension
        } else {
            pathExtension = URL(fileURLWithPath: value).pathExtension
        }
        return imageExtensions.contains(pathExtension.lowercased())
    }

    private static func previewURL(for value: String, kind: ToolArtifactKind) -> String? {
        if isInlineImageData(value) {
            return value
        }
        guard isImagePreview(for: value, kind: kind) else {
            return nil
        }
        return href(for: value, kind: kind)
    }

    private static func href(for value: String, kind: ToolArtifactKind) -> String? {
        switch kind {
        case .url:
            return value
        case .file:
            if value.hasPrefix("file://") {
                return value
            }
            if value.hasPrefix("/") {
                return URL(fileURLWithPath: value).absoluteString
            }
            return nil
        case .path:
            return nil
        }
    }

    private static func isInlineImageData(_ value: String) -> Bool {
        value.lowercased().hasPrefix("data:image/")
    }

    private static let imageExtensions: Set<String> = [
        "png",
        "jpg",
        "jpeg",
        "gif",
        "webp",
        "heic",
        "tif",
        "tiff",
        "bmp"
    ]
}

public struct ToolCardState: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var status: ToolCardStatus
    public var inputJSON: String?
    public var outputJSON: String?
    public var artifacts: [ToolArtifactState]
    public var isExpanded: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        status: ToolCardStatus,
        inputJSON: String? = nil,
        outputJSON: String? = nil,
        artifacts: [ToolArtifactState] = [],
        isExpanded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.artifacts = artifacts
        self.isExpanded = isExpanded
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case status
        case inputJSON
        case outputJSON
        case artifacts
        case isExpanded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.status = try container.decode(ToolCardStatus.self, forKey: .status)
        self.inputJSON = try container.decodeIfPresent(String.self, forKey: .inputJSON)
        self.outputJSON = try container.decodeIfPresent(String.self, forKey: .outputJSON)
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
    }

    public var imagePreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.isImagePreview)
    }
}

public struct ComposerState: Sendable, Hashable {
    public var draft: String
    public var isSending: Bool
    public var placeholder: String

    public init(
        draft: String = "",
        isSending: Bool = false,
        placeholder: String = "Message QuillCode"
    ) {
        self.draft = draft
        self.isSending = isSending
        self.placeholder = placeholder
    }
}

public struct TerminalCommandState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var ok: Bool
    public var status: TerminalCommandStatus
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.ok = ok
        self.status = status ?? (ok ? .done : .failed)
        self.createdAt = createdAt
    }
}

public enum TerminalCommandStatus: String, Sendable, Hashable {
    case running
    case done
    case failed
    case stopped
}

public struct WorkspaceWorktreeCreateRequest: Sendable, Hashable {
    public var path: String
    public var branch: String
    public var base: String

    public init(path: String, branch: String = "", base: String = "") {
        self.path = path
        self.branch = branch
        self.base = base
    }
}

public struct WorkspaceWorktreeRemoveRequest: Sendable, Hashable {
    public var path: String
    public var force: Bool

    public init(path: String, force: Bool = false) {
        self.path = path
        self.force = force
    }
}

public struct TerminalState: Sendable, Hashable {
    public var projectID: UUID?
    public var currentDirectoryPath: String?
    public var environmentOverrides: [String: String]
    public var removedEnvironmentKeys: Set<String>
    public var isVisible: Bool
    public var draft: String
    public var isRunning: Bool
    public var entries: [TerminalCommandState]

    public init(
        projectID: UUID? = nil,
        currentDirectoryPath: String? = nil,
        environmentOverrides: [String: String] = [:],
        removedEnvironmentKeys: Set<String> = [],
        isVisible: Bool = false,
        draft: String = "",
        isRunning: Bool = false,
        entries: [TerminalCommandState] = []
    ) {
        self.projectID = projectID
        self.currentDirectoryPath = currentDirectoryPath
        self.environmentOverrides = environmentOverrides
        self.removedEnvironmentKeys = removedEnvironmentKeys
        self.isVisible = isVisible
        self.draft = draft
        self.isRunning = isRunning
        self.entries = entries
    }
}

public struct BrowserCommentState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), url: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

public struct BrowserSnapshotState: Sendable, Hashable {
    public var sourceLabel: String
    public var summary: String
    public var details: [String]

    public init(sourceLabel: String, summary: String, details: [String] = []) {
        self.sourceLabel = sourceLabel
        self.summary = summary
        self.details = details
    }
}

public struct WorkspaceReviewCommentState: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var lineNumber: Int?
    public var endLineNumber: Int?
    public var lineKind: WorkspaceReviewLineKind?
    public var text: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind? = nil,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.lineNumber = lineNumber
        self.endLineNumber = endLineNumber
        self.lineKind = lineKind
        self.text = text
        self.createdAt = createdAt
    }
}

public struct BrowserState: Sendable, Hashable {
    public var isVisible: Bool
    public var addressDraft: String
    public var currentURL: String?
    public var title: String
    public var status: String
    public var snapshot: BrowserSnapshotState?
    public var comments: [BrowserCommentState]

    public init(
        isVisible: Bool = false,
        addressDraft: String = "",
        currentURL: String? = nil,
        title: String = "Browser preview",
        status: String = "Ready",
        snapshot: BrowserSnapshotState? = nil,
        comments: [BrowserCommentState] = []
    ) {
        self.isVisible = isVisible
        self.addressDraft = addressDraft
        self.currentURL = currentURL
        self.title = title
        self.status = status
        self.snapshot = snapshot
        self.comments = comments
    }
}

public struct ExtensionsState: Sendable, Hashable {
    public var isVisible: Bool
    public var mcpServerStatuses: [String: MCPServerLifecycleStatus]
    public var mcpServerProbeSummaries: [String: MCPServerProbeSummary]

    public init(
        isVisible: Bool = false,
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:]
    ) {
        self.isVisible = isVisible
        self.mcpServerStatuses = mcpServerStatuses
        self.mcpServerProbeSummaries = mcpServerProbeSummaries
    }
}

public enum MCPServerLifecycleStatus: String, Sendable, Hashable {
    case stopped
    case probing
    case running
    case ready
    case failed

    public var title: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .probing:
            return "Probing"
        case .running:
            return "Running"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }

    public var isActive: Bool {
        switch self {
        case .probing, .running, .ready:
            return true
        case .stopped, .failed:
            return false
        }
    }
}

public struct MCPServerProbeSummary: Codable, Sendable, Hashable {
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var toolNames: [String]
    public var errorMessage: String?

    public init(
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        toolNames: [String] = [],
        errorMessage: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.toolNames = toolNames
        self.errorMessage = errorMessage
    }

    public init(result: MCPServerProbeResult) {
        self.init(
            protocolVersion: result.protocolVersion,
            serverName: result.serverName,
            serverVersion: result.serverVersion,
            toolNames: result.toolNames,
            errorMessage: nil
        )
    }

    public var serverLabel: String? {
        switch (serverName, serverVersion) {
        case let (.some(name), .some(version)) where !version.isEmpty:
            return "\(name) \(version)"
        case let (.some(name), _):
            return name
        default:
            return nil
        }
    }

    public var toolCountLabel: String? {
        guard errorMessage == nil else { return nil }
        return "\(toolNames.count) tool\(toolNames.count == 1 ? "" : "s")"
    }
}

public struct MemoriesState: Sendable, Hashable {
    public var isVisible: Bool

    public init(isVisible: Bool = false) {
        self.isVisible = isVisible
    }
}

private final class MCPServerProcessHandle: @unchecked Sendable {
    let process: Process
    let standardInput: Pipe
    let standardOutput: Pipe
    let standardError: Pipe
    let session: MCPStdioProber

    init(
        process: Process,
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe,
        session: MCPStdioProber
    ) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.session = session
    }
}

private struct MCPToolCallRequest {
    var serverID: String
    var toolName: String
    var toolArgumentsJSON: String

    init(argumentsJSON: String) throws {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw MCPToolCallRequestError.invalidJSON
        }

        let serverID = (object["serverID"] as? String ?? object["serverId"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let toolName = (object["toolName"] as? String ?? object["name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverID.isEmpty else { throw MCPToolCallRequestError.missingServerID }
        guard !toolName.isEmpty else { throw MCPToolCallRequestError.missingToolName }

        if let argumentsJSON = object["argumentsJSON"] as? String,
           !argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.toolArgumentsJSON = argumentsJSON
        } else if let arguments = object["arguments"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) {
            self.toolArgumentsJSON = String(decoding: data, as: UTF8.self)
        } else {
            self.toolArgumentsJSON = "{}"
        }
        self.serverID = serverID
        self.toolName = toolName
    }
}

private enum MCPToolCallRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingToolName

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP call arguments must be a JSON object."
        case .missingServerID:
            return "MCP call requires a non-empty serverID."
        case .missingToolName:
            return "MCP call requires a non-empty toolName."
        }
    }
}

@MainActor
public final class QuillCodeWorkspaceModel {
    public private(set) var root: QuillCodeRootState
    public private(set) var composer: ComposerState
    public private(set) var terminal: TerminalState
    public private(set) var browser: BrowserState
    public private(set) var extensions: ExtensionsState
    public private(set) var memories: MemoriesState
    public private(set) var lastError: String?

    private var runner: AgentRunner
    private let threadStore: JSONThreadStore?
    private let projectStore: JSONProjectStore?
    private let globalMemoryDirectory: URL?
    private var computerUseBackend: (any ComputerUseBackend)?
    private var mcpServerProcesses: [String: MCPServerProcessHandle]

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        composer: ComposerState = ComposerState(),
        terminal: TerminalState = TerminalState(),
        browser: BrowserState = BrowserState(),
        extensions: ExtensionsState = ExtensionsState(),
        memories: MemoriesState = MemoriesState(),
        runner: AgentRunner = AgentRunner(),
        threadStore: JSONThreadStore? = nil,
        projectStore: JSONProjectStore? = nil,
        globalMemoryDirectory: URL? = nil,
        computerUseBackend: (any ComputerUseBackend)? = nil
    ) {
        self.root = root
        self.composer = composer
        self.terminal = terminal
        self.browser = browser
        self.extensions = extensions
        self.memories = memories
        self.runner = runner
        self.threadStore = threadStore
        self.projectStore = projectStore
        self.globalMemoryDirectory = globalMemoryDirectory
        self.computerUseBackend = computerUseBackend
        self.mcpServerProcesses = [:]
        if let computerUseBackend {
            self.root.topBar.computerUseStatus = computerUseBackend.status
        }
        syncTerminalSessionToSelectedProject()
        refreshTopBar()
    }

    deinit {
        for handle in mcpServerProcesses.values where handle.process.isRunning {
            handle.process.terminate()
        }
    }

    public var selectedThread: ChatThread? {
        guard let selectedThreadID = root.selectedThreadID else { return nil }
        return root.threads.first { $0.id == selectedThreadID }
    }

    public var selectedProject: ProjectRef? {
        guard let selectedProjectID = root.selectedProjectID else { return nil }
        return root.projects.first { $0.id == selectedProjectID }
    }

    public var activeWorkspaceRoot: URL? {
        selectedProject.map { URL(fileURLWithPath: $0.path) }
    }

    var terminalCurrentDirectoryURL: URL? {
        guard terminal.projectID == knownProjectID(root.selectedProjectID) else {
            return activeWorkspaceRoot
        }
        if let path = terminal.currentDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return activeWorkspaceRoot
    }

    private func syncTerminalSessionToSelectedProject() {
        let selectedProjectID = knownProjectID(root.selectedProjectID)
        guard terminal.projectID != selectedProjectID else { return }
        terminal.projectID = selectedProjectID
        terminal.currentDirectoryPath = selectedProject.map(\.path)
        terminal.environmentOverrides = [:]
        terminal.removedEnvironmentKeys = []
    }

    public var currentToolCards: [ToolCardState] {
        selectedThread.map(Self.toolCards(for:)) ?? []
    }

    public var canRetryLastUserTurn: Bool {
        guard composer.isSending == false else { return false }
        return selectedThread?.messages.contains {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } == true
    }

    public func setDraft(_ draft: String) {
        composer.draft = draft
    }

    @discardableResult
    public func setMessageFeedback(messageID: UUID, value: MessageFeedbackValue) -> Bool {
        guard selectedThread?.messages.contains(where: { $0.id == messageID && $0.role == .assistant }) == true else {
            return false
        }
        let feedback = MessageFeedback(messageID: messageID, value: value)
        guard let payloadJSON = try? JSONHelpers.encodePretty(feedback) else {
            return false
        }
        let summary: String
        switch value {
        case .helpful:
            summary = "Marked assistant response helpful"
        case .notHelpful:
            summary = "Marked assistant response not helpful"
        }
        mutateSelectedThread { thread in
            thread.events.append(ThreadEvent(
                kind: .messageFeedback,
                summary: summary,
                payloadJSON: payloadJSON
            ))
        }
        return true
    }

    @discardableResult
    public func prepareRetryLastUserTurn() -> Bool {
        guard let lastUserMessage = selectedThread?.messages.last(where: {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        composer.draft = lastUserMessage.content
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func setTerminalDraft(_ draft: String) {
        terminal.draft = draft
    }

    public func setTerminalVisible(_ isVisible: Bool) {
        terminal.isVisible = isVisible
    }

    public func toggleTerminal() {
        terminal.isVisible.toggle()
    }

    public func setBrowserAddressDraft(_ draft: String) {
        browser.addressDraft = draft
    }

    public func toggleBrowser() {
        browser.isVisible.toggle()
    }

    public func toggleExtensions() {
        extensions.isVisible.toggle()
    }

    public func toggleMemories() {
        memories.isVisible.toggle()
    }

    @discardableResult
    public func openBrowserPreview(_ input: String? = nil, workspaceRoot: URL? = nil) -> Bool {
        let rawValue = input ?? browser.addressDraft
        guard let url = Self.normalizedBrowserURL(rawValue, workspaceRoot: workspaceRoot) else {
            browser.isVisible = true
            browser.status = "Invalid address"
            lastError = "Enter an http, https, file, localhost, or project file URL."
            refreshTopBar(agentStatus: "Idle")
            return false
        }

        browser.isVisible = true
        browser.currentURL = url.absoluteString
        browser.addressDraft = url.absoluteString
        browser.snapshot = Self.browserSnapshot(for: url)
        browser.title = browser.snapshot?.details
            .first { $0.hasPrefix("Title: ") }
            .map { String($0.dropFirst("Title: ".count)) }
            ?? Self.browserTitle(for: url)
        browser.status = "Preview ready"
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = browser.currentURL else {
            return false
        }
        browser.comments.append(BrowserCommentState(url: url, text: trimmed))
        browser.status = "Comment added"
        return true
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let thread = ChatThread(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: effectiveProjectID),
            memories: memoryNotes(for: effectiveProjectID)
        )
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = effectiveProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(effectiveProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return thread.id
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let copiedMessages = Self.forkSeedMessages(from: source.messages)
        let fork = ChatThread(
            title: "Fork: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Forked from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        root.threads.insert(fork, at: 0)
        root.selectedThreadID = fork.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(fork)
        refreshTopBar(agentStatus: "Idle")
        return fork.id
    }

    @discardableResult
    public func compactContext() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let copiedMessages = Self.compactSeedMessages(from: source)
        let compacted = ChatThread(
            title: "Compact: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Compacted context from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        root.threads.insert(compacted, at: 0)
        root.selectedThreadID = compacted.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(compacted)
        refreshTopBar(agentStatus: "Idle")
        return compacted.id
    }

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let standardized = path.standardizedFileURL
        let projectName = name ?? Self.defaultProjectName(for: standardized)
        if let index = root.projects.firstIndex(where: { $0.path == standardized.path }) {
            root.projects[index].name = projectName
            root.projects[index].instructions = ProjectInstructionLoader.load(from: standardized)
            root.projects[index].localActions = LocalEnvironmentActionLoader.load(from: standardized)
            root.projects[index].extensionManifests = ProjectExtensionManifestLoader.load(from: standardized)
            root.projects[index].memories = MemoryNoteLoader.loadProject(from: standardized)
            root.projects[index].lastOpenedAt = Date()
            root.selectedProjectID = root.projects[index].id
            syncTerminalSessionToSelectedProject()
            saveProjects()
            refreshTopBar(agentStatus: "Idle")
            return root.projects[index].id
        }

        let project = ProjectRef(
            name: projectName,
            path: standardized.path,
            lastOpenedAt: Date(),
            instructions: ProjectInstructionLoader.load(from: standardized),
            localActions: LocalEnvironmentActionLoader.load(from: standardized),
            extensionManifests: ProjectExtensionManifestLoader.load(from: standardized),
            memories: MemoryNoteLoader.loadProject(from: standardized)
        )
        root.projects.insert(project, at: 0)
        root.selectedProjectID = project.id
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return project.id
    }

    public func selectProject(_ id: UUID?) {
        if let id {
            guard root.projects.contains(where: { $0.id == id }) else { return }
        }
        root.selectedProjectID = id
        syncTerminalSessionToSelectedProject()
        refreshProjectMetadata(id)
        touchProject(id)
        root.selectedThreadID = root.threads
            .filter { !$0.isArchived && $0.projectID == id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .id
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func renameProject(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = root.projects.firstIndex(where: { $0.id == id })
        else {
            return false
        }
        root.projects[index].name = trimmed
        root.projects[index].lastOpenedAt = Date()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func refreshProjectContext(_ id: UUID) -> Bool {
        guard root.projects.contains(where: { $0.id == id }) else {
            return false
        }
        refreshProjectMetadata(id)
        if selectedThread?.projectID == id || root.selectedProjectID == id {
            let refreshedInstructions = instructions(for: id)
            let refreshedMemories = memoryNotes(for: id)
            mutateSelectedThread { thread in
                guard thread.projectID == id else { return }
                thread.instructions = refreshedInstructions
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Refreshed project context",
                    payloadJSON: id.uuidString
                ))
            }
        }
        touchProject(id)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func removeProject(_ id: UUID) -> Bool {
        guard let index = root.projects.firstIndex(where: { $0.id == id }) else {
            return false
        }
        root.projects.remove(at: index)
        for threadIndex in root.threads.indices where root.threads[threadIndex].projectID == id {
            root.threads[threadIndex].projectID = nil
            try? threadStore?.save(root.threads[threadIndex])
        }
        if root.selectedProjectID == id {
            root.selectedProjectID = nil
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func togglePinSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        togglePinThread(selectedThreadID)
    }

    public func archiveSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        archiveThread(selectedThreadID)
    }

    @discardableResult
    public func renameThread(_ id: UUID, to title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard mutateThread(id, { thread in
            thread.title = trimmed
        }) != nil else {
            return false
        }
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func duplicateThread(_ id: UUID) -> UUID? {
        guard let source = root.threads.first(where: { $0.id == id }) else { return nil }
        var duplicate = ChatThread(
            title: "Copy: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: source.messages,
            events: source.events,
            isPinned: false,
            isArchived: false,
            instructions: source.instructions,
            memories: source.memories
        )
        duplicate.events.append(.init(
            kind: .notice,
            summary: "Duplicated from \(source.title)",
            payloadJSON: source.id.uuidString
        ))
        root.threads.insert(duplicate, at: 0)
        root.selectedThreadID = duplicate.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(duplicate)
        refreshTopBar(agentStatus: "Idle")
        return duplicate.id
    }

    public func togglePinThread(_ id: UUID) {
        mutateThread(id) { thread in
            thread.isPinned.toggle()
        }
    }

    public func archiveThread(_ id: UUID) {
        let archivedProjectID = root.threads.first { $0.id == id }?.projectID
        mutateThread(id) { thread in
            thread.isArchived = true
        }
        if root.selectedThreadID == id {
            root.selectedThreadID = root.threads
                .filter { !$0.isArchived && $0.projectID == archivedProjectID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?
                .id
        }
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func unarchiveThread(_ id: UUID) -> Bool {
        guard let source = root.threads.first(where: { $0.id == id }),
              mutateThread(id, { thread in
                  thread.isArchived = false
              }) != nil
        else {
            return false
        }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(source.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func deleteThread(_ id: UUID) -> Bool {
        guard let index = root.threads.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let removed = root.threads.remove(at: index)
        try? threadStore?.delete(id)
        if root.selectedThreadID == id {
            root.selectedThreadID = root.threads
                .filter { !$0.isArchived && $0.projectID == removed.projectID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?
                .id
        }
        if let selectedThread {
            root.selectedProjectID = knownProjectID(selectedThread.projectID)
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func setMode(_ mode: AgentMode) {
        root.config.mode = mode
        mutateSelectedThread { thread in
            thread.mode = mode
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func setModel(_ model: String) {
        root.config.defaultModel = model
        mutateSelectedThread { thread in
            thread.model = model
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func toggleModelFavorite(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = root.config.favoriteModels.firstIndex(of: trimmed) {
            root.config.favoriteModels.remove(at: index)
        } else {
            root.config.favoriteModels.append(trimmed)
        }
        root.config.favoriteModels = AppConfig(favoriteModels: root.config.favoriteModels).favoriteModels
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setModelCatalog(_ models: [ModelInfo]) {
        guard !models.isEmpty else { return }
        root.modelCatalog = TrustedRouterDefaults.catalogIncludingBundledDefaults(models)
    }

    public func applySettings(config: AppConfig, trustedRouterAPIKeyConfigured: Bool) {
        root.config = config
        root.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured
        mutateSelectedThread { thread in
            thread.mode = config.mode
            thread.model = config.defaultModel
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func applyRuntime(_ runtime: QuillCodeRuntime) {
        runner = runtime.runner
        refreshTopBar(agentStatus: runtime.statusLabel)
    }

    public func setAgentStatus(_ status: String, lastError: String? = nil) {
        self.lastError = lastError
        refreshTopBar(agentStatus: status)
    }

    public func submitComposer(workspaceRoot: URL) async {
        let prompt = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if let command = SlashCommandParser.parse(prompt) {
            composer.draft = ""
            lastError = nil
            handleSlashCommand(command, originalPrompt: prompt, workspaceRoot: workspaceRoot)
            return
        }

        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return }
        syncThreadContext(into: &thread)
        let threadID = thread.id

        composer.draft = ""
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        do {
            try Task.checkCancellation()
            let activeMCPToolDefinition = mcpToolDefinitionForReadyServers()
            let activeMCPExecutor = mcpToolExecutionOverride()
            let activeComputerDefinitions = computerUseBackend == nil ? [] : ToolDefinition.computerUseDefinitions
            let activeComputerExecutor = computerUseToolExecutionOverride()
            var activeRunner = runner
            activeRunner.additionalToolDefinitions = activeComputerDefinitions + (activeMCPToolDefinition.map { [$0] } ?? [])
            activeRunner.toolExecutionOverride = combinedToolExecutionOverride(
                computerUse: activeComputerExecutor,
                mcp: activeMCPExecutor
            )

            let result = try await activeRunner.send(
                prompt,
                in: thread,
                workspaceRoot: workspaceRoot,
                onProgress: { [weak self] progressThread in
                    await self?.applyAgentProgress(progressThread, expectedThreadID: threadID)
                }
            )
            try Task.checkCancellation()
            thread = result.thread
            replaceThread(thread)
            try threadStore?.save(thread)
            composer.isSending = false
            refreshTopBar(agentStatus: "Idle")
        } catch is CancellationError {
            finishCancelledSend(userPrompt: prompt, threadID: threadID)
        } catch {
            composer.isSending = false
            lastError = String(describing: error)
            refreshTopBar(agentStatus: "Failed")
        }
    }

    private func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard thread.id == expectedThreadID else { return }
        replaceThread(thread)
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: agentStatus(for: thread))
    }

    private func agentStatus(for thread: ChatThread) -> String {
        switch thread.events.last?.kind {
        case .toolQueued:
            return "Queued"
        case .toolRunning:
            return "Running"
        case .approvalRequested:
            return "Review"
        case .notice where thread.events.last?.summary == AgentRunner.streamingNotice:
            return "Streaming"
        case .toolCompleted:
            return "Finishing"
        case .toolFailed:
            return "Failed"
        case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice, .none:
            return "Running"
        }
    }

    public func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let actionCall = action.toolCall
        let actionResult = router.execute(actionCall)
        appendToolRun(call: actionCall, result: actionResult)

        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult = router.execute(diffCall)
        appendToolRun(call: diffCall, result: diffResult)

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: actionResult.ok && diffResult.ok ? "Idle" : "Failed")
    }

    @discardableResult
    public func addReviewComment(path: String, text: String) -> Bool {
        addReviewComment(path: path, lineNumber: nil, endLineNumber: nil, lineKind: nil, text: text)
    }

    @discardableResult
    public func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedThread != nil,
              !trimmedPath.isEmpty,
              !trimmedText.isEmpty
        else {
            return false
        }

        let currentReview = surface().review
        guard let file = currentReview.files.first(where: { $0.path == trimmedPath }) else {
            return false
        }

        let normalizedRange = Self.normalizedReviewRange(
            lineNumber: lineNumber,
            endLineNumber: endLineNumber
        )
        if let normalizedRange {
            guard Self.reviewRangeExists(normalizedRange, lineKind: lineKind, in: file) else {
                return false
            }
        }

        let comment = WorkspaceReviewCommentState(
            path: trimmedPath,
            lineNumber: normalizedRange?.lowerBound,
            endLineNumber: normalizedRange?.upperBound,
            lineKind: lineKind,
            text: trimmedText
        )
        let payloadJSON = (try? JSONHelpers.encodePretty(comment)) ?? "{}"
        let summary = normalizedRange.map { range in
            range.lowerBound == range.upperBound
                ? "Commented on \(trimmedPath):\(range.lowerBound)"
                : "Commented on \(trimmedPath):\(range.lowerBound)-\(range.upperBound)"
        } ?? "Commented on \(trimmedPath)"
        mutateSelectedThread { thread in
            thread.events.append(.init(
                kind: .reviewComment,
                summary: summary,
                payloadJSON: payloadJSON
            ))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    private static func normalizedReviewRange(
        lineNumber: Int?,
        endLineNumber: Int?
    ) -> ClosedRange<Int>? {
        guard let lineNumber else { return nil }
        let endLineNumber = endLineNumber ?? lineNumber
        guard lineNumber > 0, endLineNumber > 0 else { return nil }
        return min(lineNumber, endLineNumber)...max(lineNumber, endLineNumber)
    }

    private static func reviewRangeExists(
        _ range: ClosedRange<Int>,
        lineKind: WorkspaceReviewLineKind?,
        in file: WorkspaceReviewFileSurface
    ) -> Bool {
        let lines = file.hunkItems.flatMap(\.lines)
        guard lines.contains(where: {
            $0.displayLineNumber == range.lowerBound
                && (lineKind == nil || $0.kind == lineKind)
        }) else {
            return false
        }
        return range.allSatisfy { number in
            lines.contains { $0.displayLineNumber == number }
        }
    }

    @discardableResult
    public func runWorkspaceCommand(_ commandID: String, workspaceRoot: URL) -> Bool {
        if commandID.hasPrefix("local-env:") {
            return runLocalEnvironmentAction(commandID, workspaceRoot: workspaceRoot)
        }
        if commandID.hasPrefix("memory-delete:") {
            let id = String(commandID.dropFirst("memory-delete:".count))
            return deleteGlobalMemory(id: id)
        }
        if commandID.hasPrefix("mcp-start:") {
            let id = String(commandID.dropFirst("mcp-start:".count))
            return startMCPServer(id: id, workspaceRoot: workspaceRoot)
        }
        if commandID.hasPrefix("mcp-stop:") {
            let id = String(commandID.dropFirst("mcp-stop:".count))
            return stopMCPServer(id: id)
        }
        switch commandID {
        case "toggle-terminal":
            toggleTerminal()
            return true
        case "toggle-browser":
            toggleBrowser()
            return true
        case "toggle-extensions":
            toggleExtensions()
            return true
        case "toggle-memories":
            toggleMemories()
            return true
        case "memory-add":
            composer.draft = "/remember "
            return true
        case "project-new-chat":
            guard let projectID = root.selectedProjectID else { return false }
            _ = newChat(projectID: projectID)
            return true
        case "project-refresh-context":
            guard let projectID = root.selectedProjectID else { return false }
            return refreshProjectContext(projectID)
        case "project-rename":
            guard let name = selectedProject?.name else { return false }
            composer.draft = "/project rename \(name)"
            return true
        case "project-remove":
            guard let projectID = root.selectedProjectID else { return false }
            return removeProject(projectID)
        case "thread-rename":
            guard let title = selectedThread?.title else { return false }
            composer.draft = "/rename \(title)"
            return true
        case "thread-duplicate":
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return duplicateThread(selectedThreadID) != nil
        case "thread-archive":
            guard let selectedThreadID = root.selectedThreadID else { return false }
            archiveThread(selectedThreadID)
            return true
        case "thread-unarchive":
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return unarchiveThread(selectedThreadID)
        case "thread-delete":
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return deleteThread(selectedThreadID)
        case "retry-last-turn":
            return prepareRetryLastUserTurn()
        case "fork-from-last":
            return forkFromLast() != nil
        case "compact-context":
            return compactContext() != nil
        case "git-worktree-list":
            runToolCall(
                ToolCall(name: ToolDefinition.gitWorktreeList.name, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
            return true
        case "git-pr-create":
            setDraft("Create a pull request titled ")
            return true
        case "git-worktree-create":
            setDraft("Create a git worktree named ")
            return true
        case "git-worktree-remove":
            setDraft("Remove git worktree at ")
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func startMCPServer(id: String, workspaceRoot: URL) -> Bool {
        guard let manifest = selectedProject?.extensionManifests.first(where: {
            $0.id == id && $0.kind == .mcpServer
        }) else {
            lastError = "MCP server manifest not found."
            return false
        }
        guard manifest.isEnabled else {
            lastError = "\(manifest.name) is disabled."
            extensions.mcpServerStatuses[id] = .failed
            return false
        }
        guard let command = manifest.launchExecutable,
              !command.isEmpty
        else {
            lastError = "\(manifest.name) does not define a launch command."
            extensions.mcpServerStatuses[id] = .failed
            return false
        }
        if let handle = mcpServerProcesses[id], handle.process.isRunning {
            if extensions.mcpServerStatuses[id]?.isActive != true {
                extensions.mcpServerStatuses[id] = .running
            }
            refreshTopBar(agentStatus: "Idle")
            return true
        }

        let process = Process()
        process.currentDirectoryURL = workspaceRoot
        let arguments = manifest.launchArguments ?? []
        if command.contains("/") {
            let commandURL = command.hasPrefix("/")
                ? URL(fileURLWithPath: command)
                : workspaceRoot.appendingPathComponent(command)
            process.executableURL = commandURL
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                self?.finishMCPServerProcess(id: id, terminationStatus: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            lastError = "Could not start \(manifest.name): \(error.localizedDescription)"
            extensions.mcpServerStatuses[id] = .failed
            refreshTopBar(agentStatus: "Failed")
            appendNotice("MCP server \(manifest.name) failed to start")
            return false
        }

        let session = MCPStdioProber(
            standardInput: standardInput.fileHandleForWriting,
            standardOutput: standardOutput.fileHandleForReading
        )
        let handle = MCPServerProcessHandle(
            process: process,
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError,
            session: session
        )
        mcpServerProcesses[id] = handle
        extensions.mcpServerStatuses[id] = .probing
        extensions.mcpServerProbeSummaries[id] = nil
        lastError = nil
        refreshTopBar(agentStatus: "Idle")

        do {
            let result = try session.probe(timeout: 2.0)
            extensions.mcpServerStatuses[id] = .ready
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(result: result)
            standardError.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
            appendNotice("MCP server \(manifest.name) ready\(mcpToolNoticeSuffix(for: result.toolNames))")
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }
            mcpServerProcesses[id] = nil
            let message = error.localizedDescription
            lastError = "Could not verify \(manifest.name): \(message)"
            extensions.mcpServerStatuses[id] = .failed
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(errorMessage: message)
            refreshTopBar(agentStatus: "Failed")
            appendNotice("MCP server \(manifest.name) probe failed: \(message)")
            return false
        }
        return true
    }

    @discardableResult
    private func stopMCPServer(id: String) -> Bool {
        guard let manifest = selectedProject?.extensionManifests.first(where: {
            $0.id == id && $0.kind == .mcpServer
        }) else {
            lastError = "MCP server manifest not found."
            return false
        }

        if let handle = mcpServerProcesses[id], handle.process.isRunning {
            handle.standardOutput.fileHandleForReading.readabilityHandler = nil
            handle.standardError.fileHandleForReading.readabilityHandler = nil
            handle.process.terminate()
        }
        mcpServerProcesses[id] = nil
        extensions.mcpServerStatuses[id] = .stopped
        extensions.mcpServerProbeSummaries[id] = nil
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        appendNotice("MCP server \(manifest.name) stopped")
        return true
    }

    private func finishMCPServerProcess(id: String, terminationStatus: Int32) {
        mcpServerProcesses[id] = nil
        if extensions.mcpServerStatuses[id] == .stopped {
            return
        }
        extensions.mcpServerStatuses[id] = terminationStatus == 0 ? .stopped : .failed
        if terminationStatus != 0 {
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(
                errorMessage: "Process exited with status \(terminationStatus)."
            )
        } else {
            extensions.mcpServerProbeSummaries[id] = nil
        }
        refreshTopBar(agentStatus: terminationStatus == 0 ? "Idle" : "Failed")
    }

    private func mcpToolNoticeSuffix(for toolNames: [String]) -> String {
        guard !toolNames.isEmpty else { return " (0 tools)" }
        let preview = toolNames.prefix(3).joined(separator: ", ")
        let remaining = toolNames.count - min(toolNames.count, 3)
        if remaining > 0 {
            return " (\(toolNames.count) tools: \(preview), +\(remaining) more)"
        }
        return " (\(toolNames.count) tools: \(preview))"
    }

    private func mcpToolDefinitionForReadyServers() -> ToolDefinition? {
        let ready = readyMCPToolDescriptions()
        guard !ready.isEmpty else { return nil }
        var definition = ToolDefinition.mcpCall
        definition.description = """
        Call a tool on a verified project-local MCP stdio server. Use only these Ready MCP tools:
        \(ready.joined(separator: "\n"))
        """
        return definition
    }

    private func readyMCPToolDescriptions() -> [String] {
        (selectedProject?.extensionManifests ?? [])
            .filter { manifest in
                manifest.kind == .mcpServer
                    && extensions.mcpServerStatuses[manifest.id] == .ready
                    && mcpServerProcesses[manifest.id]?.process.isRunning == true
            }
            .compactMap { manifest -> String? in
                let tools = extensions.mcpServerProbeSummaries[manifest.id]?.toolNames ?? []
                guard !tools.isEmpty else { return nil }
                return "- \(manifest.id) (\(manifest.name)): \(tools.joined(separator: ", "))"
            }
    }

    private func mcpToolExecutionOverride() -> AgentToolExecutionOverride? {
        let sessions = mcpServerProcesses.compactMapValues { handle in
            handle.process.isRunning ? handle.session : nil
        }
        let allowedTools = extensions.mcpServerProbeSummaries.mapValues { Set($0.toolNames) }
        guard !sessions.isEmpty else { return nil }

        return { call, _ in
            guard call.name == ToolDefinition.mcpCall.name else { return nil }
            do {
                let request = try MCPToolCallRequest(argumentsJSON: call.argumentsJSON)
                guard let session = sessions[request.serverID] else {
                    return ToolResult(ok: false, error: "MCP server is not running or is not Ready: \(request.serverID)")
                }
                guard allowedTools[request.serverID]?.contains(request.toolName) == true else {
                    return ToolResult(
                        ok: false,
                        error: "MCP tool \(request.toolName) was not advertised by \(request.serverID)."
                    )
                }
                return try session.callTool(
                    toolName: request.toolName,
                    argumentsJSON: request.toolArgumentsJSON
                )
            } catch {
                return ToolResult(ok: false, error: Self.mcpUserFacingError(error))
            }
        }
    }

    private func computerUseToolExecutionOverride() -> AgentToolExecutionOverride? {
        guard let computerUseBackend else { return nil }
        let executor = ComputerUseToolExecutor(backend: computerUseBackend)
        return { call, _ in
            await executor.execute(call)
        }
    }

    private func combinedToolExecutionOverride(
        computerUse: AgentToolExecutionOverride?,
        mcp: AgentToolExecutionOverride?
    ) -> AgentToolExecutionOverride? {
        guard computerUse != nil || mcp != nil else { return nil }
        return { call, workspaceRoot in
            if let result = await computerUse?(call, workspaceRoot) {
                return result
            }
            if let result = await mcp?(call, workspaceRoot) {
                return result
            }
            return nil
        }
    }

    private nonisolated static func mcpUserFacingError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }

    private func appendNotice(_ summary: String) {
        mutateSelectedThread { thread in
            thread.events.append(.init(kind: .notice, summary: summary))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
    }

    @discardableResult
    private func deleteGlobalMemory(id: String) -> Bool {
        guard let globalMemoryDirectory else { return false }
        do {
            let note = try MemoryNoteLoader.deleteGlobal(id: id, from: globalMemoryDirectory)
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(
                userText: "Forget memory: \(note.title)",
                assistantText: "Forgot memory: \(note.title). It will no longer be included as background context.",
                title: "Forgot memory: \(note.title)"
            )
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Forgot memory: \(note.title)",
                    payloadJSON: note.relativePath
                ))
            }
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch let error as MemoryNoteDeleteError {
            appendLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: error.localizedDescription,
                title: "Memory not deleted"
            )
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch {
            appendLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: MemoryNoteDeleteError.deleteFailed.localizedDescription,
                title: "Memory not deleted"
            )
            refreshTopBar(agentStatus: "Idle")
            return true
        }
    }

    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = localAction(withID: actionID) else {
            return false
        }
        runToolCall(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: toolArgumentsJSON(["cmd": action.command])
            ),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    public func createWorktree(_ request: WorkspaceWorktreeCreateRequest, workspaceRoot: URL) {
        var arguments: [String: Any] = ["path": request.path]
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = request.base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            arguments["branch"] = branch
        }
        if !base.isEmpty {
            arguments["base"] = base
        }
        let result = runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openCreatedWorktree(result, request: request)
        }
    }

    public func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest, workspaceRoot: URL) {
        runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeRemove.name,
                argumentsJSON: toolArgumentsJSON([
                    "path": request.path,
                    "force": request.force
                ])
            ),
            workspaceRoot: workspaceRoot
        )
    }

    @discardableResult
    public func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        if selectedThread == nil {
            _ = newChat()
        }
        guard selectedThread != nil else {
            return ToolResult(ok: false, error: "No active thread")
        }
        let contextProjectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectMetadata(contextProjectID)
        let refreshedMemories = memoryNotes(for: contextProjectID)
        let refreshedInstructions = instructions(for: contextProjectID)
        mutateSelectedThread { thread in
            thread.memories = refreshedMemories
            thread.instructions = refreshedInstructions
        }
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let result = router.execute(call)
        appendToolRun(call: call, result: result)
        let followUpResult = appendReviewDiffAfterPatchIfNeeded(
            call: call,
            result: result,
            router: router
        )

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        let ok = result.ok && (followUpResult?.ok ?? true)
        refreshTopBar(agentStatus: ok ? "Idle" : "Failed")
        return result
    }

    public func runTerminalCommand(workspaceRoot: URL) async {
        await runTerminalCommand(terminal.draft, workspaceRoot: workspaceRoot)
    }

    public func runTerminalCommand(_ input: String, workspaceRoot: URL) async {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !terminal.isRunning else { return }
        syncTerminalSessionToSelectedProject()

        let workingDirectory = terminalCurrentDirectoryURL ?? workspaceRoot.standardizedFileURL
        let executionContext = Self.terminalExecutionContext(
            command: command,
            workingDirectory: workingDirectory,
            environment: Self.effectiveTerminalEnvironment(
                overrides: terminal.environmentOverrides,
                removedKeys: terminal.removedEnvironmentKeys
            )
        )

        let entryID = UUID()
        terminal.draft = ""
        terminal.isVisible = true
        terminal.isRunning = true
        terminal.entries.append(TerminalCommandState(
            id: entryID,
            command: command,
            stdout: "",
            stderr: "",
            exitCode: nil,
            ok: false,
            status: .running
        ))
        lastError = nil
        refreshTopBar(agentStatus: "Terminal")

        var finalResult: ToolResult?
        for await event in ShellToolExecutor().runStreaming(executionContext.request) {
            if Task.isCancelled || terminal.entries.first(where: { $0.id == entryID })?.status == .stopped {
                break
            }
            switch event {
            case .stdout(let text):
                appendTerminalOutput(id: entryID, stdout: text)
            case .stderr(let text):
                appendTerminalOutput(id: entryID, stderr: text)
            case .finished(let result):
                finalResult = result
            }
        }

        if terminal.entries.first(where: { $0.id == entryID })?.status == .stopped {
            Self.removeTerminalMarkers(executionContext.markerURLs)
            terminal.isRunning = false
            refreshTopBar(agentStatus: "Stopped")
            return
        }
        guard !Task.isCancelled, let result = finalResult else {
            Self.removeTerminalMarkers(executionContext.markerURLs)
            finishTerminalEntry(
                id: entryID,
                stdout: "",
                stderr: "Command stopped.",
                exitCode: nil,
                ok: false,
                status: .stopped
            )
            terminal.isRunning = false
            lastError = nil
            refreshTopBar(agentStatus: "Stopped")
            return
        }

        terminal.currentDirectoryPath = Self.terminalCurrentDirectoryPath(
            markerURL: executionContext.cwdMarkerURL,
            fallback: workingDirectory
        )
        if let environmentDelta = Self.terminalEnvironmentDelta(markerURL: executionContext.environmentMarkerURL) {
            terminal.environmentOverrides = environmentDelta.overrides
            terminal.removedEnvironmentKeys = environmentDelta.removedKeys
        }
        finishTerminalEntry(
            id: entryID,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            ok: result.ok,
            status: result.ok ? .done : .failed
        )
        terminal.isRunning = false
        refreshTopBar(agentStatus: result.ok ? "Idle" : "Failed")
    }

    private func appendTerminalOutput(id: UUID, stdout: String = "", stderr: String = "") {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }),
              terminal.entries[index].status == .running else {
            return
        }
        terminal.entries[index].stdout += stdout
        terminal.entries[index].stderr += stderr
    }

    private struct TerminalExecutionContext {
        var request: ShellExecutionRequest
        var cwdMarkerURL: URL
        var environmentMarkerURL: URL

        var markerURLs: [URL] {
            [cwdMarkerURL, environmentMarkerURL]
        }
    }

    private static func terminalExecutionContext(
        command: String,
        workingDirectory: URL,
        environment: [String: String]
    ) -> TerminalExecutionContext {
        let markerID = UUID().uuidString
        let markerDirectory = FileManager.default.temporaryDirectory
        let cwdMarkerURL = markerDirectory.appendingPathComponent("quillcode-terminal-\(markerID).cwd")
        let environmentMarkerURL = markerDirectory.appendingPathComponent("quillcode-terminal-\(markerID).env")
        let cwdMarkerPath = shellSingleQuoted(cwdMarkerURL.path)
        let environmentMarkerPath = shellSingleQuoted(environmentMarkerURL.path)
        let wrappedCommand = """
        \(command)
        status=$?
        printf '%s\n' "$PWD" > \(cwdMarkerPath)
        /usr/bin/env -0 > \(environmentMarkerPath)
        exit "$status"
        """
        return TerminalExecutionContext(
            request: ShellExecutionRequest(
                command: wrappedCommand,
                cwd: workingDirectory,
                environment: environment
            ),
            cwdMarkerURL: cwdMarkerURL,
            environmentMarkerURL: environmentMarkerURL
        )
    }

    private static func terminalCurrentDirectoryPath(markerURL: URL, fallback: URL) -> String {
        defer { removeTerminalMarker(at: markerURL) }
        guard let rawPath = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return fallback.standardizedFileURL.path
        }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return fallback.standardizedFileURL.path
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private struct TerminalEnvironmentDelta {
        var overrides: [String: String]
        var removedKeys: Set<String>
    }

    private static let ignoredTerminalEnvironmentDeltaKeys: Set<String> = [
        "PWD",
        "OLDPWD",
        "SHLVL",
        "_"
    ]

    private static func effectiveTerminalEnvironment(
        overrides: [String: String],
        removedKeys: Set<String>
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in removedKeys {
            environment.removeValue(forKey: key)
        }
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    private static func terminalEnvironmentDelta(markerURL: URL) -> TerminalEnvironmentDelta? {
        defer { removeTerminalMarker(at: markerURL) }
        guard let data = try? Data(contentsOf: markerURL) else {
            return nil
        }
        let finalEnvironment = terminalEnvironment(from: data)
        let baseEnvironment = ProcessInfo.processInfo.environment
        var overrides: [String: String] = [:]
        for (key, value) in finalEnvironment
            where baseEnvironment[key] != value
                && !ignoredTerminalEnvironmentDeltaKeys.contains(key) {
            overrides[key] = value
        }
        let removedKeys = Set(baseEnvironment.keys.filter {
            finalEnvironment[$0] == nil && !ignoredTerminalEnvironmentDeltaKeys.contains($0)
        })
        return TerminalEnvironmentDelta(overrides: overrides, removedKeys: removedKeys)
    }

    private static func terminalEnvironment(from data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in data.split(separator: 0, omittingEmptySubsequences: true) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let equalsIndex = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equalsIndex])
            let value = String(text[text.index(after: equalsIndex)...])
            guard !key.isEmpty else { continue }
            environment[key] = value
        }
        return environment
    }

    private static func removeTerminalMarkers(_ urls: [URL]) {
        for url in urls {
            removeTerminalMarker(at: url)
        }
    }

    private static func removeTerminalMarker(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func finishTerminalEntry(
        id: UUID,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus
    ) {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }) else { return }
        if terminal.entries[index].status == .stopped, status != .stopped {
            return
        }
        terminal.entries[index].stdout = stdout
        terminal.entries[index].stderr = stderr
        terminal.entries[index].exitCode = exitCode
        terminal.entries[index].ok = ok
        terminal.entries[index].status = status
    }

    public func cancelActiveWork() {
        let runningMCPIDs = mcpServerProcesses.compactMap { id, handle in
            handle.process.isRunning ? id : nil
        }
        let hadActiveWork = composer.isSending || terminal.isRunning || !runningMCPIDs.isEmpty
        composer.isSending = false
        terminal.isRunning = false
        for index in terminal.entries.indices where terminal.entries[index].status == .running {
            terminal.entries[index].stderr = terminal.entries[index].stderr.isEmpty
                ? "Command stopped."
                : terminal.entries[index].stderr
            terminal.entries[index].exitCode = nil
            terminal.entries[index].ok = false
            terminal.entries[index].status = .stopped
        }
        for id in runningMCPIDs {
            mcpServerProcesses[id]?.standardOutput.fileHandleForReading.readabilityHandler = nil
            mcpServerProcesses[id]?.standardError.fileHandleForReading.readabilityHandler = nil
            mcpServerProcesses[id]?.process.terminate()
            mcpServerProcesses[id] = nil
            extensions.mcpServerStatuses[id] = .stopped
            extensions.mcpServerProbeSummaries[id] = nil
        }
        lastError = nil
        if hadActiveWork {
            refreshTopBar(agentStatus: "Stopped")
        }
    }

    public static func toolCards(for thread: ChatThread) -> [ToolCardState] {
        var cards: [ToolCardState] = []
        var activeToolCardIndex: Int?

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolCardIndex else {
                return
            }
            updateCard(&cards, at: index, status: status, subtitle: subtitle, outputJSON: outputJSON)
            if status == .done || status == .failed {
                activeToolCardIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .toolQueued:
                let call = decode(ToolCall.self, event.payloadJSON)
                cards.append(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
                activeToolCardIndex = cards.count - 1
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                cards.append(ToolCardState(
                    id: event.id.uuidString,
                    title: "Safety Check",
                    subtitle: event.summary,
                    status: .review,
                    inputJSON: event.payloadJSON,
                    isExpanded: true
                ))
            case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        return cards
    }

    public static func messageSurfaces(for thread: ChatThread) -> [MessageSurface] {
        let feedbackByMessageID = messageFeedbackByMessageID(for: thread)
        return thread.messages
            .filter { $0.role != .tool }
            .map { message in
                MessageSurface(message: message, feedback: feedbackByMessageID[message.id])
            }
    }

    public static func transcriptTimelineItems(for thread: ChatThread) -> [TranscriptTimelineItemSurface] {
        guard !thread.events.isEmpty else {
            return messageSurfaces(for: thread).map(TranscriptTimelineItemSurface.message)
                + toolCards(for: thread).map(TranscriptTimelineItemSurface.toolCard)
        }

        let feedbackByMessageID = messageFeedbackByMessageID(for: thread)
        var consumedMessageIDs = Set<UUID>()
        var items: [TranscriptTimelineItemSurface] = []
        var activeToolItemIndex: Int?

        func appendMessage(matching summary: String) {
            guard let message = thread.messages.first(where: {
                !consumedMessageIDs.contains($0.id) && $0.content == summary
            }) else {
                return
            }
            consumedMessageIDs.insert(message.id)
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }

        func appendToolCard(_ card: ToolCardState) {
            items.append(.toolCard(card))
            activeToolItemIndex = items.count - 1
        }

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolItemIndex,
                  var card = items[index].toolCard
            else {
                appendToolCard(ToolCardState(
                    id: "orphan-\(UUID().uuidString)",
                    title: "Tool",
                    subtitle: subtitle,
                    status: status,
                    outputJSON: outputJSON,
                    artifacts: outputJSON.map(Self.artifacts(from:)) ?? []
                ))
                return
            }
            card.status = status
            card.subtitle = subtitle
            if let outputJSON {
                card.outputJSON = outputJSON
                card.artifacts = Self.artifacts(from: outputJSON)
            }
            items[index] = .toolCard(card)
            if status == .done || status == .failed {
                activeToolItemIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .message:
                appendMessage(matching: event.summary)
            case .toolQueued:
                let call = decode(ToolCall.self, event.payloadJSON)
                appendToolCard(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                items.append(.toolCard(ToolCardState(
                    id: event.id.uuidString,
                    title: "Safety Check",
                    subtitle: event.summary,
                    status: .review,
                    inputJSON: event.payloadJSON,
                    isExpanded: true
                )))
            case .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        for message in thread.messages where message.role != .tool && !consumedMessageIDs.contains(message.id) {
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }
        return items
    }

    private static func messageFeedbackByMessageID(for thread: ChatThread) -> [UUID: MessageFeedbackValue] {
        var feedbackByMessageID: [UUID: MessageFeedbackValue] = [:]
        for event in thread.events where event.kind == .messageFeedback {
            guard let feedback = decode(MessageFeedback.self, event.payloadJSON) else { continue }
            feedbackByMessageID[feedback.messageID] = feedback.value
        }
        return feedbackByMessageID
    }

    private func appendToolRun(call: ToolCall, result: ToolResult) {
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? call.argumentsJSON
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        mutateSelectedThread { thread in
            thread.events.append(.init(
                kind: .toolQueued,
                summary: "\(call.name) queued",
                payloadJSON: callJSON
            ))
            thread.events.append(.init(
                kind: .toolRunning,
                summary: "\(call.name) running"
            ))
            thread.events.append(.init(
                kind: result.ok ? .toolCompleted : .toolFailed,
                summary: "\(call.name) \(result.ok ? "completed" : "failed")",
                payloadJSON: resultJSON
            ))
        }
    }

    private func openCreatedWorktree(_ result: ToolResult, request: WorkspaceWorktreeCreateRequest) {
        guard let artifact = result.artifacts.first else { return }
        let worktreeURL = URL(fileURLWithPath: artifact).standardizedFileURL
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return }

        let projectID = addProject(path: worktreeURL, name: Self.defaultProjectName(for: worktreeURL))
        refreshProjectMetadata(projectID)

        let titleLabel = Self.worktreeThreadLabel(request: request, url: worktreeURL)
        let messageText = "Opened worktree `\(worktreeURL.lastPathComponent)` at `\(worktreeURL.path)`."
        let message = ChatMessage(role: .assistant, content: messageText)
        let thread = ChatThread(
            title: "Worktree: \(titleLabel)",
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            messages: [message],
            events: [
                .init(
                    kind: .notice,
                    summary: "Opened worktree \(worktreeURL.lastPathComponent)",
                    payloadJSON: worktreeURL.path
                ),
                .init(kind: .message, summary: messageText)
            ],
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID)
        )

        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = projectID
        syncTerminalSessionToSelectedProject()
        touchProject(projectID)
        saveProjects()
        try? threadStore?.save(thread)
        refreshTopBar(agentStatus: "Idle")
    }

    private static func worktreeThreadLabel(request: WorkspaceWorktreeCreateRequest, url: URL) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        return defaultProjectName(for: url)
    }

    @discardableResult
    private func appendReviewDiffAfterPatchIfNeeded(
        call: ToolCall,
        result: ToolResult,
        router: ToolRouter
    ) -> ToolResult? {
        guard call.name == ToolDefinition.applyPatch.name, result.ok else {
            return nil
        }
        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult = router.execute(diffCall)
        appendToolRun(call: diffCall, result: diffResult)
        return diffResult
    }

    private func toolArgumentsJSON(_ values: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) {
        switch command {
        case .help:
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: SlashCommandCatalog.helpText(),
                title: "Slash commands"
            )
        case .status:
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: statusText(),
                title: "Status"
            )
        case .newChat:
            _ = newChat()
        case .mode(let mode):
            setMode(mode)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Mode set to \(Self.modeLabel(mode)).",
                title: "Set mode"
            )
        case .model(let model):
            setModel(model)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Model set to \(model).",
                title: "Set model"
            )
        case .renameThread(let title):
            if let id = root.selectedThreadID, renameThread(id, to: title) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Renamed chat to \(title.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    title: "Rename chat"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not rename this chat. Try /rename New chat title.",
                    title: "Rename chat"
                )
            }
        case .renameProject(let name):
            if let id = root.selectedProjectID, renameProject(id, to: name) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Renamed project to \(name.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    title: "Rename project"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not rename this project. Try /project rename New project name.",
                    title: "Rename project"
                )
            }
        case .remember(let content):
            runRememberSlashCommand(content, originalPrompt: originalPrompt)
        case .workspaceCommand(let commandID):
            if !runWorkspaceCommand(commandID, workspaceRoot: workspaceRoot) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not run /\(originalPrompt.dropFirst()). Try /help.",
                    title: "Slash command"
                )
            }
        case .environmentAction(let query):
            runEnvironmentSlashCommand(query, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
        case .invalid(let message):
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: message,
                title: "Slash command"
            )
        case .unknown(let name):
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Unknown slash command '/\(name)'. Try /help.",
                title: "Slash command"
            )
        }
        composer.isSending = false
        refreshTopBar(agentStatus: "Idle")
    }

    private func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        guard let globalMemoryDirectory else {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: MemoryNoteWriteError.unavailable.localizedDescription,
                title: "Memory not saved"
            )
            return
        }

        do {
            let note = try MemoryNoteLoader.saveGlobal(content: content, to: globalMemoryDirectory)
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Saved memory: \(note.title). It will be included as background context in future turns.",
                title: "Memory: \(note.title)"
            )
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Saved memory: \(note.title)",
                    payloadJSON: note.relativePath
                ))
            }
        } catch let error as MemoryNoteWriteError {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: error.localizedDescription,
                title: "Memory not saved"
            )
        } catch {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: MemoryNoteWriteError.writeFailed.localizedDescription,
                title: "Memory not saved"
            )
        }
    }

    private func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let actions = selectedProject?.localActions ?? []
            let message: String
            if actions.isEmpty {
                message = "No local environment actions found. Add scripts under `.quillcode/actions` or `.quillcode/local-env`."
            } else {
                let rows = actions
                    .map { "- `/env \($0.title)` — \($0.relativePath)" }
                    .joined(separator: "\n")
                message = "Local environment actions:\n\(rows)"
            }
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: message,
                title: "Local environment actions"
            )
            return
        }

        guard let action = localAction(matching: query) else {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "No local environment action matches `\(query)`. Run `/env` to see available actions.",
                title: "Local environment actions"
            )
            return
        }
        _ = runLocalEnvironmentAction(action.id, workspaceRoot: workspaceRoot)
    }

    private func appendLocalCommandTranscript(userText: String, assistantText: String, title: String) {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = title
            }
            thread.messages.append(ChatMessage(role: .user, content: userText))
            thread.messages.append(ChatMessage(role: .assistant, content: assistantText))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
    }

    private func finishCancelledSend(userPrompt: String, threadID: UUID) {
        composer.isSending = false
        lastError = nil
        mutateThread(threadID) { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = Self.title(fromUserPrompt: userPrompt)
            }
            if !thread.messages.contains(where: { $0.role == .user && $0.content == userPrompt }) {
                thread.messages.append(ChatMessage(role: .user, content: userPrompt))
            }
            let summary = "Stopped by user"
            if let lastEvent = thread.events.last,
               lastEvent.kind == .toolQueued || lastEvent.kind == .toolRunning {
                thread.events.append(.init(
                    kind: .toolFailed,
                    summary: summary,
                    payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
                ))
            }
            if thread.events.last?.kind != .notice || thread.events.last?.summary != summary {
                thread.events.append(.init(kind: .notice, summary: summary))
            }
        }
        refreshTopBar(agentStatus: "Stopped")
    }

    private static func title(fromUserPrompt userPrompt: String) -> String {
        let words = userPrompt.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }

    private static func forkSeedMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        let visibleMessages = visibleConversationMessages(from: messages)
        guard let lastUserIndex = visibleMessages.lastIndex(where: { $0.role == .user }) else {
            return Array(visibleMessages.suffix(4))
        }
        return Array(visibleMessages[lastUserIndex...].prefix(4))
    }

    private static func compactSeedMessages(from thread: ChatThread) -> [ChatMessage] {
        let visibleMessages = visibleConversationMessages(from: thread.messages)
        let recentMessages = forkSeedMessages(from: visibleMessages)
        let recentIDs = Set(recentMessages.map(\.id))
        let olderMessages = visibleMessages.filter { !recentIDs.contains($0.id) }
        return [compactSummaryMessage(
            sourceTitle: thread.title,
            olderMessages: olderMessages,
            recentMessages: recentMessages
        )] + recentMessages
    }

    private static func visibleConversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .tool }
    }

    private static func compactSummaryMessage(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) -> ChatMessage {
        let olderCount = olderMessages.count
        let recentCount = recentMessages.count
        var lines = [
            "Context compacted from \"\(sourceTitle)\".",
            "Kept \(recentCount) latest message\(recentCount == 1 ? "" : "s") and summarized \(olderCount) earlier message\(olderCount == 1 ? "" : "s")."
        ]
        if olderMessages.isEmpty {
            lines.append("No earlier turns were dropped.")
        } else {
            lines.append("Earlier context:")
            for message in olderMessages.suffix(6) {
                lines.append("- \(roleLabel(message.role)): \(singleLineExcerpt(message.content, limit: 180))")
            }
        }
        lines.append("Continue from the preserved latest turn below.")
        return ChatMessage(role: .assistant, content: lines.joined(separator: "\n"))
    }

    private static func roleLabel(_ role: ChatRole) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        }
    }

    private static func singleLineExcerpt(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func statusText() -> String {
        let project = selectedProject?.name ?? root.topBar.projectName ?? "No project"
        let thread = selectedThread?.title ?? "No chat"
        let instructionLabel = Self.instructionStatusLabel(for: selectedProject?.instructions ?? selectedThread?.instructions ?? [])
        let memoryLabel = Self.memoryStatusLabel(for: selectedThread?.memories ?? memoryNotes(for: root.selectedProjectID))
        return """
        Project: \(project)
        Thread: \(thread)
        Instructions: \(instructionLabel)
        Memories: \(memoryLabel)
        Mode: \(Self.modeLabel(root.topBar.mode))
        Model: \(root.topBar.model)
        Agent: \(root.topBar.agentStatus)
        """
    }

    private func mutateSelectedThread(_ update: (inout ChatThread) -> Void) {
        guard let selectedThreadID = root.selectedThreadID,
              let index = mutateThread(selectedThreadID, update)
        else {
            return
        }
        root.selectedThreadID = root.threads[index].id
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    @discardableResult
    private func mutateThread(_ id: UUID, _ update: (inout ChatThread) -> Void) -> Int? {
        guard let index = root.threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        update(&root.threads[index])
        root.threads[index].updatedAt = Date()
        try? threadStore?.save(root.threads[index])
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return index
    }

    private func replaceThread(_ thread: ChatThread) {
        if let index = root.threads.firstIndex(where: { $0.id == thread.id }) {
            root.threads[index] = thread
        } else {
            root.threads.insert(thread, at: 0)
        }
        root.selectedThreadID = thread.id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
    }

    public func setComputerUseStatus(_ status: ComputerUseStatus) {
        root.topBar.computerUseStatus = status
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setComputerUseBackend(_ backend: any ComputerUseBackend) {
        computerUseBackend = backend
        setComputerUseStatus(backend.status)
    }

    public func refreshSelectedProjectInstructions() {
        refreshSelectedProjectContext()
    }

    public func refreshSelectedProjectContext() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshGlobalMemories()
        refreshProjectMetadata(projectID)
        let refreshedInstructions = instructions(for: projectID)
        let refreshedMemories = memoryNotes(for: projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedInstructions
            thread.memories = refreshedMemories
        }
        saveProjects()
    }

    private func refreshTopBar(agentStatus: String? = nil) {
        let thread = selectedThread
        let projectID = thread?.projectID ?? root.selectedProjectID
        let project = projectID.flatMap { id in root.projects.first { $0.id == id } }
        root.topBar = TopBarState(
            projectName: project?.name,
            threadTitle: thread?.title,
            model: thread?.model ?? root.config.defaultModel,
            mode: thread?.mode ?? root.config.mode,
            agentStatus: agentStatus ?? root.topBar.agentStatus,
            computerUseStatus: root.topBar.computerUseStatus
        )
    }

    private func touchProject(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        root.projects[index].lastOpenedAt = Date()
    }

    private func refreshProjectInstructions(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        root.projects[index].instructions = ProjectInstructionLoader.load(from: rootURL)
        root.projects[index].memories = MemoryNoteLoader.loadProject(from: rootURL)
    }

    private func refreshProjectMetadata(_ id: UUID?) {
        refreshGlobalMemories()
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        root.projects[index].instructions = ProjectInstructionLoader.load(from: rootURL)
        root.projects[index].localActions = LocalEnvironmentActionLoader.load(from: rootURL)
        root.projects[index].extensionManifests = ProjectExtensionManifestLoader.load(from: rootURL)
        root.projects[index].memories = MemoryNoteLoader.loadProject(from: rootURL)
    }

    private func refreshGlobalMemories() {
        guard let globalMemoryDirectory else { return }
        root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
    }

    private func syncThreadContext(into thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        thread.instructions = instructions(for: projectID)
        thread.memories = memoryNotes(for: projectID)
    }

    private func instructions(for projectID: UUID?) -> [ProjectInstruction] {
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID })
        else {
            return []
        }
        return project.instructions
    }

    private func memoryNotes(for projectID: UUID?) -> [MemoryNote] {
        let projectMemories: [MemoryNote]
        if let projectID,
           let project = root.projects.first(where: { $0.id == projectID }) {
            projectMemories = project.memories
        } else {
            projectMemories = []
        }
        return root.globalMemories + projectMemories
    }

    private func localAction(withID id: String) -> LocalEnvironmentAction? {
        selectedProject?.localActions.first { $0.id == id }
    }

    private func localAction(matching query: String) -> LocalEnvironmentAction? {
        let normalizedQuery = Self.normalizedActionName(query)
        return selectedProject?.localActions.first { action in
            action.id.caseInsensitiveCompare(query) == .orderedSame
                || action.title.caseInsensitiveCompare(query) == .orderedSame
                || action.relativePath.caseInsensitiveCompare(query) == .orderedSame
                || Self.normalizedActionName(action.title) == normalizedQuery
                || Self.normalizedActionName(action.relativePath) == normalizedQuery
        }
    }

    private static func normalizedActionName(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func instructionStatusLabel(for instructions: [ProjectInstruction]) -> String {
        guard !instructions.isEmpty else { return "No project instructions" }
        let truncated = instructions.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(instructions.count) instruction file\(instructions.count == 1 ? "" : "s") loaded\(truncated)"
    }

    static func memoryStatusLabel(for memories: [MemoryNote]) -> String {
        guard !memories.isEmpty else { return "No memories" }
        let truncated = memories.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(memories.count) memor\(memories.count == 1 ? "y" : "ies")\(truncated)"
    }

    private func knownProjectID(_ id: UUID?) -> UUID? {
        guard let id, root.projects.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func saveProjects() {
        try? projectStore?.save(root.projects)
    }

    private static func defaultProjectName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    private static func normalizedBrowserURL(_ rawValue: String, workspaceRoot: URL?) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return url
        }

        if trimmed.hasPrefix("localhost")
            || trimmed.hasPrefix("127.0.0.1")
            || trimmed.hasPrefix("[::1]") {
            return URL(string: "http://\(trimmed)")
        }

        if let workspaceRoot,
           let fileURL = projectFileBrowserURL(trimmed, workspaceRoot: workspaceRoot) {
            return fileURL
        }

        if trimmed.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL.standardizedFileURL
            }
        }

        if trimmed.contains(".") {
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }

    private static func projectFileBrowserURL(_ relativePath: String, workspaceRoot: URL) -> URL? {
        guard !relativePath.contains("..") else { return nil }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard (fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/")),
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return nil
        }
        return fileURL
    }

    private static func browserTitle(for url: URL) -> String {
        if url.isFileURL {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return url.host ?? url.absoluteString
    }

    private static let browserSnapshotMaxBytes = 512_000

    private static func browserSnapshot(for url: URL) -> BrowserSnapshotState {
        if url.isFileURL {
            return fileBrowserSnapshot(for: url)
        }

        let scheme = (url.scheme ?? "https").uppercased()
        let host = url.host ?? url.absoluteString
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
        let sourceLabel = isLocal ? "Local web app" : "Web page"
        let path = url.path.isEmpty ? "/" : url.path
        return BrowserSnapshotState(
            sourceLabel: sourceLabel,
            summary: isLocal
                ? "Ready to inspect a local development page."
                : "Ready to open in the browser preview.",
            details: [
                "Host: \(host)",
                "Scheme: \(scheme)",
                "Path: \(path)"
            ]
        )
    }

    private static func fileBrowserSnapshot(for url: URL) -> BrowserSnapshotState {
        let fileName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let extensionName = url.pathExtension.lowercased()
        let isHTML = ["html", "htm", "xhtml"].contains(extensionName)
        var details = ["File: \(fileName)", "Size: \(byteCount) bytes"]

        guard isHTML else {
            return BrowserSnapshotState(
                sourceLabel: "Local file",
                summary: "File is ready to open in the browser preview.",
                details: details
            )
        }

        details.insert("Type: HTML", at: 1)
        guard byteCount <= browserSnapshotMaxBytes,
              let data = try? Data(contentsOf: url),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        else {
            details.append("Snapshot: skipped because the file is too large or unreadable")
            return BrowserSnapshotState(
                sourceLabel: "Local HTML",
                summary: "HTML file is ready to open; metadata snapshot was skipped.",
                details: details
            )
        }

        if let title = firstHTMLCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#) {
            details.append("Title: \(title)")
        }
        if let heading = firstHTMLCapture(in: html, pattern: #"<h[1-2][^>]*>(.*?)</h[1-2]>"#) {
            details.append("Heading: \(heading)")
        }
        details.append("Links: \(htmlTagCount("a", in: html))")
        details.append("Scripts: \(htmlTagCount("script", in: html))")
        details.append("Images: \(htmlTagCount("img", in: html))")
        details.append("Forms: \(htmlTagCount("form", in: html))")

        return BrowserSnapshotState(
            sourceLabel: "Local HTML",
            summary: "HTML snapshot captured for browser review.",
            details: details
        )
    }

    private static func firstHTMLCapture(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        return cleanHTMLText(String(html[captureRange]))
    }

    private static func htmlTagCount(_ tag: String, in html: String) -> Int {
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\s*\#(escapedTag)(\s|>|/)"#,
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.numberOfMatches(in: html, range: range)
    }

    private static func cleanHTMLText(_ raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func updateCard(
        _ cards: inout [ToolCardState],
        at index: Int,
        status: ToolCardStatus,
        subtitle: String,
        outputJSON: String? = nil
    ) {
        guard cards.indices.contains(index) else { return }
        cards[index].status = status
        cards[index].subtitle = subtitle
        if let outputJSON {
            cards[index].outputJSON = outputJSON
            cards[index].artifacts = artifacts(from: outputJSON)
        }
    }

    private static func artifacts(from outputJSON: String) -> [ToolArtifactState] {
        guard let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON) else {
            return []
        }
        return result.artifacts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(ToolArtifactState.init(value:))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}

private extension WorkspaceReviewActionSurface {
    var toolCall: ToolCall {
        switch kind {
        case .stage:
            return ToolCall(
                name: ToolDefinition.gitStage.name,
                argumentsJSON: ToolArguments.json(["path": path])
            )
        case .restore:
            return ToolCall(
                name: ToolDefinition.gitRestore.name,
                argumentsJSON: ToolArguments.json(["path": path])
            )
        case .stageHunk:
            return ToolCall(
                name: ToolDefinition.gitStageHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": path,
                    "patch": patch ?? ""
                ])
            )
        case .restoreHunk:
            return ToolCall(
                name: ToolDefinition.gitRestoreHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": path,
                    "patch": patch ?? ""
                ])
            )
        }
    }
}
