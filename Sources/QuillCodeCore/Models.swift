import Foundation

public enum AgentMode: String, Codable, Sendable, CaseIterable {
    case readOnly = "read-only"
    case review
    case auto
}

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var role: ChatRole
    public var content: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum ToolHost: String, Codable, Sendable {
    case local
    case browser
    case computer
    case plugin
    case mcp
}

public enum ToolRiskClass: String, Codable, Sendable {
    case read
    case append
    case destructive
}

public struct ToolDefinition: Codable, Sendable, Hashable {
    public var name: String
    public var description: String
    public var parametersJSON: String
    public var host: ToolHost
    public var risk: ToolRiskClass

    public init(
        name: String,
        description: String,
        parametersJSON: String,
        host: ToolHost = .local,
        risk: ToolRiskClass = .read
    ) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
        self.host = host
        self.risk = risk
    }
}

public enum AgentPlanItemStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case completed

    public var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .inProgress:
            return "Running"
        case .completed:
            return "Done"
        }
    }
}

public struct AgentPlanItem: Codable, Sendable, Hashable {
    public var step: String
    public var status: AgentPlanItemStatus
    public var detail: String?

    public init(step: String, status: AgentPlanItemStatus, detail: String? = nil) {
        self.step = step
        self.status = status
        self.detail = detail
    }
}

public struct AgentPlanUpdate: Codable, Sendable, Hashable {
    public var explanation: String?
    public var plan: [AgentPlanItem]

    public init(explanation: String? = nil, plan: [AgentPlanItem]) {
        self.explanation = explanation
        self.plan = plan
    }
}

public struct ToolCall: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var argumentsJSON: String

    public init(id: String = "tool-\(UUID().uuidString)", name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ToolResult: Codable, Sendable, Hashable {
    public var ok: Bool
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var error: String?
    public var artifacts: [String]

    public init(
        ok: Bool,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = nil,
        error: String? = nil,
        artifacts: [String] = []
    ) {
        self.ok = ok
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.error = error
        self.artifacts = artifacts
    }
}

public struct BrowserInspectionComment: Codable, Sendable, Hashable {
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(url: String, text: String, createdAt: Date) {
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

public enum BrowserInspectionDepth: String, Codable, Sendable, Hashable, CaseIterable {
    case metadataOnly = "metadata_only"
    case fileMetadata = "file_metadata"
    case staticHTMLSnapshot = "static_html_snapshot"

    public var label: String {
        switch self {
        case .metadataOnly:
            return "Metadata only"
        case .fileMetadata:
            return "File metadata"
        case .staticHTMLSnapshot:
            return "Static HTML snapshot"
        }
    }
}

public struct BrowserInspectionToolOutput: Codable, Sendable, Hashable {
    public var url: String
    public var title: String
    public var status: String
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?
    public var comments: [BrowserInspectionComment]

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case status
        case sourceLabel
        case inspectionDepth
        case summary
        case details
        case outline
        case textSnippet
        case comments
    }

    public init(
        url: String,
        title: String,
        status: String,
        sourceLabel: String,
        inspectionDepth: BrowserInspectionDepth = .metadataOnly,
        summary: String,
        details: [String],
        outline: [String] = [],
        textSnippet: String? = nil,
        comments: [BrowserInspectionComment] = []
    ) {
        self.url = url
        self.title = title
        self.status = status
        self.sourceLabel = sourceLabel
        self.inspectionDepth = inspectionDepth
        self.summary = summary
        self.details = details
        self.outline = outline
        self.textSnippet = textSnippet
        self.comments = comments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(String.self, forKey: .status)
        self.sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        self.inspectionDepth = try container.decodeIfPresent(
            BrowserInspectionDepth.self,
            forKey: .inspectionDepth
        ) ?? .metadataOnly
        self.summary = try container.decode(String.self, forKey: .summary)
        self.details = try container.decode([String].self, forKey: .details)
        self.outline = try container.decodeIfPresent([String].self, forKey: .outline) ?? []
        self.textSnippet = try container.decodeIfPresent(String.self, forKey: .textSnippet)
        self.comments = try container.decodeIfPresent(
            [BrowserInspectionComment].self,
            forKey: .comments
        ) ?? []
    }
}

public struct MemoryRememberToolOutput: Codable, Sendable, Hashable {
    public var title: String
    public var relativePath: String
    public var content: String

    public init(title: String, relativePath: String, content: String) {
        self.title = title
        self.relativePath = relativePath
        self.content = content
    }
}

public extension ToolDefinition {
    static let planUpdate = ToolDefinition(
        name: "host.plan.update",
        description: "Update the visible task plan for the current thread. Use this before or during multi-step work so the Activity pane reflects the model-authored plan. Provide 1-12 concise steps and at most one in_progress item.",
        parametersJSON: #"{"type":"object","properties":{"explanation":{"type":"string"},"plan":{"type":"array","minItems":1,"maxItems":12,"items":{"type":"object","properties":{"step":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]},"detail":{"type":"string"}},"required":["step","status"]}}},"required":["plan"]}"#,
        host: .local,
        risk: .read
    )

    static let browserInspect = ToolDefinition(
        name: "host.browser.inspect",
        description: "Inspect the current QuillCode browser preview page, including URL, title, inspection depth, summary, visible page outline, text snippet, and attached browser comments.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .browser,
        risk: .read
    )

    static let memoryRemember = ToolDefinition(
        name: "host.memory.remember",
        description: "Save a durable user preference or stable project fact as explicit memory for future turns. Use only when the user asks QuillCode to remember something, or when the preference/fact is clearly stable and useful. Never save credentials, tokens, passwords, private keys, or other secrets.",
        parametersJSON: #"{"type":"object","properties":{"content":{"type":"string","description":"The durable preference or stable fact to remember. Do not include credentials, tokens, passwords, private keys, or other secrets."},"reason":{"type":"string","description":"Optional short rationale for why this should become durable memory."}},"required":["content"]}"#,
        host: .local,
        risk: .append
    )
}

public enum ApprovalVerdict: String, Codable, Sendable {
    case approve
    case deny
    case clarify
}

public struct ApprovalRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var toolCall: ToolCall
    public var toolDefinition: ToolDefinition?
    public var reason: String

    public init(
        id: String = "approval-\(UUID().uuidString)",
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        reason: String
    ) {
        self.id = id
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.reason = reason
    }
}

public struct ApprovalDecision: Codable, Sendable, Hashable {
    public var requestID: String
    public var verdict: ApprovalVerdict
    public var rationale: String

    public init(requestID: String, verdict: ApprovalVerdict, rationale: String) {
        self.requestID = requestID
        self.verdict = verdict
        self.rationale = rationale
    }
}

public enum ThreadEventKind: String, Codable, Sendable {
    case message
    case toolQueued
    case toolRunning
    case toolCompleted
    case toolFailed
    case approvalRequested
    case approvalDecided
    case reviewComment
    case notice
    case messageFeedback
}

public struct ThreadEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: ThreadEventKind
    public var createdAt: Date
    public var summary: String
    public var payloadJSON: String?

    public init(
        id: UUID = UUID(),
        kind: ThreadEventKind,
        createdAt: Date = Date(),
        summary: String,
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.summary = summary
        self.payloadJSON = payloadJSON
    }
}

public enum MessageFeedbackValue: String, Codable, Sendable, Hashable {
    case helpful
    case notHelpful
}

public struct MessageFeedback: Codable, Sendable, Hashable {
    public var messageID: UUID
    public var value: MessageFeedbackValue

    public init(messageID: UUID, value: MessageFeedbackValue) {
        self.messageID = messageID
        self.value = value
    }
}

public enum QuillAutomationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case threadFollowUp = "thread_follow_up"
    case workspaceSchedule = "workspace_schedule"
    case monitor

    public var label: String {
        switch self {
        case .threadFollowUp:
            return "Thread follow-up"
        case .workspaceSchedule:
            return "Workspace schedule"
        case .monitor:
            return "Monitor"
        }
    }
}

public enum QuillAutomationStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case active
    case paused

    public var label: String {
        switch self {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        }
    }
}

public enum QuillAutomationScheduleKind: String, Codable, Sendable, Hashable, CaseIterable {
    case heartbeat
    case cron
    case event

    public var label: String {
        switch self {
        case .heartbeat:
            return "Heartbeat"
        case .cron:
            return "Cron"
        case .event:
            return "Event"
        }
    }
}

public struct QuillAutomation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var kind: QuillAutomationKind
    public var status: QuillAutomationStatus
    public var scheduleKind: QuillAutomationScheduleKind
    public var scheduleDescription: String
    public var projectID: UUID?
    public var threadID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var nextRunAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        kind: QuillAutomationKind,
        status: QuillAutomationStatus = .active,
        scheduleKind: QuillAutomationScheduleKind,
        scheduleDescription: String,
        projectID: UUID? = nil,
        threadID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.status = status
        self.scheduleKind = scheduleKind
        self.scheduleDescription = scheduleDescription
        self.projectID = projectID
        self.threadID = threadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextRunAt = nextRunAt
    }

    public static func sortedForDisplay(_ automations: [QuillAutomation]) -> [QuillAutomation] {
        automations.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .active
            }
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case let (lhsRun?, rhsRun?) where lhsRun != rhsRun:
                return lhsRun < rhsRun
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

public enum ProjectConnectionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case local
    case ssh
}

public struct ProjectConnection: Codable, Sendable, Hashable {
    public var kind: ProjectConnectionKind
    public var path: String
    public var host: String?
    public var user: String?
    public var port: Int?

    public init(
        kind: ProjectConnectionKind,
        path: String,
        host: String? = nil,
        user: String? = nil,
        port: Int? = nil
    ) {
        self.kind = kind
        self.path = path
        self.host = host
        self.user = user
        self.port = port
    }

    public static func local(path: String) -> ProjectConnection {
        ProjectConnection(kind: .local, path: path)
    }

    public static func ssh(path: String, host: String, user: String? = nil, port: Int? = nil) -> ProjectConnection {
        ProjectConnection(kind: .ssh, path: path, host: host, user: user, port: port)
    }

    public static func parseSSH(_ value: String) -> ProjectConnection? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           components.scheme == "ssh",
           let host = components.host,
           !host.isEmpty {
            let path = components.path.isEmpty ? "/" : components.path
            return .ssh(path: path, host: host, user: components.user, port: components.port)
        }

        guard let separatorIndex = trimmed.firstIndex(of: ":") else { return nil }
        let left = String(trimmed[..<separatorIndex])
        let path = String(trimmed[trimmed.index(after: separatorIndex)...])
        guard !left.isEmpty, path.hasPrefix("/") || path.hasPrefix("~") else { return nil }

        let userAndHost = left.split(separator: "@", maxSplits: 1).map(String.init)
        let user = userAndHost.count == 2 ? userAndHost[0] : nil
        let host = userAndHost.count == 2 ? userAndHost[1] : userAndHost[0]
        guard !host.isEmpty else { return nil }
        return .ssh(path: path, host: host, user: user)
    }

    public var isRemote: Bool {
        kind != .local
    }

    public var displayLabel: String {
        switch kind {
        case .local:
            return path
        case .ssh:
            let userPrefix = user.map { "\($0)@" } ?? ""
            let hostLabel = host ?? "ssh"
            let portSuffix = port.map { ":\($0)" } ?? ""
            return "ssh://\(userPrefix)\(hostLabel)\(portSuffix)\(path)"
        }
    }

    public var kindLabel: String {
        switch kind {
        case .local:
            return "Local"
        case .ssh:
            return "SSH Remote"
        }
    }
}

public struct ProjectRef: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var connection: ProjectConnection
    public var instructions: [ProjectInstruction]
    public var localActions: [LocalEnvironmentAction]
    public var extensionManifests: [ProjectExtensionManifest]
    public var memories: [MemoryNote]
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        connection: ProjectConnection? = nil,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        localActions: [LocalEnvironmentAction] = [],
        extensionManifests: [ProjectExtensionManifest] = [],
        memories: [MemoryNote] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.connection = connection ?? .local(path: path)
        self.instructions = instructions
        self.localActions = localActions
        self.extensionManifests = extensionManifests
        self.memories = memories
        self.lastOpenedAt = lastOpenedAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        localActions: [LocalEnvironmentAction] = []
    ) {
        self.init(
            id: id,
            name: name,
            path: path,
            lastOpenedAt: lastOpenedAt,
            instructions: instructions,
            localActions: localActions,
            extensionManifests: [],
            memories: []
        )
    }

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        localActions: [LocalEnvironmentAction] = [],
        memories: [MemoryNote]
    ) {
        self.init(
            id: id,
            name: name,
            path: path,
            lastOpenedAt: lastOpenedAt,
            instructions: instructions,
            localActions: localActions,
            extensionManifests: [],
            memories: memories
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case connection
        case instructions
        case localActions
        case extensionManifests
        case memories
        case lastOpenedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.connection = try container.decodeIfPresent(ProjectConnection.self, forKey: .connection) ?? .local(path: path)
        self.instructions = try container.decodeIfPresent([ProjectInstruction].self, forKey: .instructions) ?? []
        self.localActions = try container.decodeIfPresent([LocalEnvironmentAction].self, forKey: .localActions) ?? []
        self.extensionManifests = try container.decodeIfPresent([ProjectExtensionManifest].self, forKey: .extensionManifests) ?? []
        self.memories = try container.decodeIfPresent([MemoryNote].self, forKey: .memories) ?? []
        self.lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(connection, forKey: .connection)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(localActions, forKey: .localActions)
        try container.encode(extensionManifests, forKey: .extensionManifests)
        try container.encode(memories, forKey: .memories)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    }

    public var isRemote: Bool {
        connection.isRemote
    }

    public var displayPath: String {
        connection.displayLabel
    }
}

public struct ProjectInstruction: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var content: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(
        path: String,
        title: String,
        content: String,
        byteCount: Int,
        wasTruncated: Bool = false
    ) {
        self.path = path
        self.title = title
        self.content = content
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }
}

public struct LocalEnvironmentAction: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?
    public var relativePath: String
    public var command: String
    public var sortOrder: Int?
    public var environment: [String: String]?
    public var workingDirectory: String?
    public var timeoutSeconds: Int?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        relativePath: String,
        command: String,
        sortOrder: Int? = nil,
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeoutSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.relativePath = relativePath
        self.command = command
        self.sortOrder = sortOrder
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum ProjectExtensionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case plugin
    case skill
    case mcpServer = "mcp_server"

    public var title: String {
        switch self {
        case .plugin:
            return "Plugin"
        case .skill:
            return "Skill"
        case .mcpServer:
            return "MCP"
        }
    }
}

public enum ProjectExtensionTransport: String, Codable, Sendable, Hashable {
    case stdio
    case http
    case sse
}

public struct ProjectExtensionManifest: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ProjectExtensionKind
    public var name: String
    public var summary: String
    public var relativePath: String
    public var isEnabled: Bool
    public var transport: ProjectExtensionTransport?
    public var launchExecutable: String?
    public var launchCommand: String?
    public var launchArguments: [String]?

    public init(
        id: String,
        kind: ProjectExtensionKind,
        name: String,
        summary: String = "",
        relativePath: String,
        isEnabled: Bool = true,
        transport: ProjectExtensionTransport? = nil,
        launchExecutable: String? = nil,
        launchCommand: String? = nil,
        launchArguments: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.relativePath = relativePath
        self.isEnabled = isEnabled
        self.transport = transport
        self.launchExecutable = launchExecutable
        self.launchCommand = launchCommand
        self.launchArguments = launchArguments
    }
}

public enum MemoryScope: String, Codable, Sendable, Hashable {
    case global
    case project

    public var title: String {
        switch self {
        case .global:
            return "Global"
        case .project:
            return "Project"
        }
    }
}

public struct MemoryNote: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var scope: MemoryScope
    public var title: String
    public var content: String
    public var relativePath: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(
        id: String,
        scope: MemoryScope,
        title: String,
        content: String,
        relativePath: String,
        byteCount: Int,
        wasTruncated: Bool = false
    ) {
        self.id = id
        self.scope = scope
        self.title = title
        self.content = content
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }
}

public struct ChatThread: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var projectID: UUID?
    public var instructions: [ProjectInstruction]
    public var memories: [MemoryNote]
    public var mode: AgentMode
    public var model: String
    public var messages: [ChatMessage]
    public var events: [ThreadEvent]
    public var isPinned: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        projectID: UUID? = nil,
        mode: AgentMode = .auto,
        model: String = TrustedRouterDefaults.defaultModel,
        messages: [ChatMessage] = [],
        events: [ThreadEvent] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = []
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.instructions = instructions
        self.memories = memories
        self.mode = mode
        self.model = model
        self.messages = messages
        self.events = events
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case projectID
        case instructions
        case memories
        case mode
        case model
        case messages
        case events
        case isPinned
        case isArchived
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        self.instructions = try container.decodeIfPresent([ProjectInstruction].self, forKey: .instructions) ?? []
        self.memories = try container.decodeIfPresent([MemoryNote].self, forKey: .memories) ?? []
        self.mode = try container.decode(AgentMode.self, forKey: .mode)
        self.model = TrustedRouterDefaults.normalizedDefaultModelID(try container.decode(String.self, forKey: .model))
        self.messages = try container.decode([ChatMessage].self, forKey: .messages)
        self.events = try container.decode([ThreadEvent].self, forKey: .events)
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.isArchived = try container.decode(Bool.self, forKey: .isArchived)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(memories, forKey: .memories)
        try container.encode(mode, forKey: .mode)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(events, forKey: .events)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct ModelInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String

    public init(id: String, provider: String, displayName: String, category: String) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.category = category
    }
}

public struct ModelSortKey: Sendable, Hashable, Comparable {
    public var recommendedRank: Int
    public var provider: String
    public var displayName: String
    public var id: String

    public init(recommendedRank: Int, provider: String, displayName: String, id: String) {
        self.recommendedRank = recommendedRank
        self.provider = provider
        self.displayName = displayName
        self.id = id
    }

    public static func < (lhs: ModelSortKey, rhs: ModelSortKey) -> Bool {
        if lhs.recommendedRank != rhs.recommendedRank {
            return lhs.recommendedRank < rhs.recommendedRank
        }
        if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
        if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
        return lhs.id < rhs.id
    }
}

public enum TrustedRouterDefaults {
    public static let fastModel = "trustedrouter/fast"
    public static let fusionModel = "tr/fusion"
    public static let defaultModel = fastModel
    public static let defaultAPIBaseURL = "https://api.trustedrouter.com/v1"
    public static let signInURL = "https://trustedrouter.com/sign-in-with-trustedrouter"
    public static let loopbackCallbackURL = "http://localhost:3000/callback"
    public static let safetyPrimaryModel = "glm-5.2"
    public static let safetyFallbackModel = "kimi-k2.6"
    public static let recommendedCategory = "Recommended"
    public static let safetyCategory = "Safety"
    public static let currentCategory = "Current"
    public static let trustedRouterProvider = "trustedrouter"
    public static let trustedRouterProviderAliases: [String: String] = ["tr": trustedRouterProvider]
    public static let recommendedModelIDs = [fastModel, fusionModel]
    public static let modelIDAliases: [String: String] = [
        "tr/fast": fastModel,
        "trustedrouter/fusion": fusionModel
    ]
    public static let safetyPrimaryCatalogModel = "z-ai/glm-5.2"
    public static let safetyFallbackCatalogModel = "moonshotai/kimi-k2.6"
    public static let safetyReviewerModelIDs = [safetyPrimaryCatalogModel, safetyFallbackCatalogModel]

    public static let bundledModelCatalog: [ModelInfo] = [
        .init(id: fastModel, provider: trustedRouterProvider, displayName: "Fast", category: recommendedCategory),
        .init(id: fusionModel, provider: trustedRouterProvider, displayName: "Fusion", category: recommendedCategory),
        .init(id: safetyPrimaryCatalogModel, provider: "z-ai", displayName: "GLM 5.2", category: safetyCategory),
        .init(id: safetyFallbackCatalogModel, provider: "moonshotai", displayName: "Kimi K2.6", category: safetyCategory)
    ]

    public static func canonicalProvider(_ provider: String) -> String {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trustedRouterProviderAliases[normalized] ?? normalized
    }

    public static func canonicalModelID(_ id: String) -> String {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return modelIDAliases[normalized] ?? normalized
    }

    public static func normalizedDefaultModelID(_ id: String) -> String {
        let modelID = canonicalModelID(id)
        return modelID.isEmpty ? defaultModel : modelID
    }

    public static func provider(fromModelID modelID: String) -> String {
        let canonicalID = canonicalModelID(modelID)
        if let prefix = canonicalID.split(separator: "/").first {
            return canonicalProvider(String(prefix))
        }
        return trustedRouterProvider
    }

    public static func displayName(fromModelID modelID: String) -> String {
        let raw = canonicalModelID(modelID).split(separator: "/").last.map(String.init) ?? modelID
        return raw
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public static func category(forModelID modelID: String, provider: String) -> String {
        if isRecommendedModel(modelID) {
            return recommendedCategory
        }
        if isSafetyReviewerModel(modelID) {
            return safetyCategory
        }
        return canonicalProvider(provider)
    }

    public static func displayLabel(for model: ModelInfo) -> String {
        if canonicalProvider(model.provider) == trustedRouterProvider {
            return model.id
        }
        return "\(model.provider)/\(model.displayName)"
    }

    public static func recommendedRank(for modelID: String) -> Int? {
        recommendedModelIDs.firstIndex(of: canonicalModelID(modelID))
    }

    public static func modelSortKey(id: String, provider: String, displayName: String) -> ModelSortKey {
        ModelSortKey(
            recommendedRank: recommendedRank(for: id) ?? Int.max,
            provider: canonicalProvider(provider),
            displayName: displayName,
            id: canonicalModelID(id)
        )
    }

    public static func modelCategoryRank(_ category: String) -> Int {
        switch category {
        case recommendedCategory:
            return 0
        case safetyCategory:
            return 1
        default:
            return 2
        }
    }

    public static func isRecommendedModel(_ modelID: String, provider _: String? = nil) -> Bool {
        recommendedRank(for: modelID) != nil
    }

    public static func isSafetyReviewerModel(_ modelID: String) -> Bool {
        safetyReviewerModelIDs.contains(modelID)
            || modelID == safetyPrimaryModel
            || modelID == safetyFallbackModel
    }

    public static func fallbackModelInfo(for id: String, category: String = currentCategory) -> ModelInfo {
        let modelID = canonicalModelID(id)
        let provider = provider(fromModelID: modelID)
        return ModelInfo(
            id: modelID,
            provider: provider,
            displayName: displayName(fromModelID: modelID),
            category: category
        )
    }

    public static func normalizedModelInfo(_ model: ModelInfo) -> ModelInfo {
        let modelID = canonicalModelID(model.id)
        let provider = canonicalProvider(
            model.provider.isEmpty ? provider(fromModelID: modelID) : model.provider
        )
        let displayName = model.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let category = model.category
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelInfo(
            id: modelID,
            provider: provider,
            displayName: displayName.isEmpty ? Self.displayName(fromModelID: modelID) : displayName,
            category: category.isEmpty ? Self.category(forModelID: modelID, provider: provider) : category
        )
    }

    public static func normalizedModelCatalog(_ models: [ModelInfo]) -> [ModelInfo] {
        var seen = Set<String>()
        var catalog: [ModelInfo] = []
        for model in bundledModelCatalog + models {
            let normalized = normalizedModelInfo(model)
            guard seen.insert(normalized.id).inserted else { continue }
            catalog.append(normalized)
        }
        return catalog.sorted(by: compareModels)
    }

    public static func compareModelCategories(_ lhs: String, _ rhs: String) -> Bool {
        let lhsRank = modelCategoryRank(lhs)
        let rhsRank = modelCategoryRank(rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs < rhs
    }

    public static func compareModels(_ lhs: ModelInfo, _ rhs: ModelInfo) -> Bool {
        let lhsCategoryRank = modelCategoryRank(lhs.category)
        let rhsCategoryRank = modelCategoryRank(rhs.category)
        if lhsCategoryRank != rhsCategoryRank { return lhsCategoryRank < rhsCategoryRank }
        return modelSortKey(id: lhs.id, provider: lhs.provider, displayName: lhs.displayName)
            < modelSortKey(id: rhs.id, provider: rhs.provider, displayName: rhs.displayName)
    }
}

public enum TrustedRouterAuthMode: String, Codable, Sendable, CaseIterable, Hashable {
    case oauth
    case developerOverride = "developer-override"
}

public struct TrustedRouterAccountProfile: Codable, Sendable, Hashable {
    public var userID: String?
    public var subject: String?
    public var email: String?
    public var walletAddress: String?

    public init(
        userID: String? = nil,
        subject: String? = nil,
        email: String? = nil,
        walletAddress: String? = nil
    ) {
        self.userID = Self.trimmed(userID)
        self.subject = Self.trimmed(subject)
        self.email = Self.trimmed(email)
        self.walletAddress = Self.trimmed(walletAddress)
    }

    public var isEmpty: Bool {
        [userID, subject, email, walletAddress].allSatisfy { ($0 ?? "").isEmpty }
    }

    public var displayLabel: String {
        if let email, !email.isEmpty { return email }
        if let userID, !userID.isEmpty { return userID }
        if let subject, !subject.isEmpty { return subject }
        if let walletAddress, !walletAddress.isEmpty { return walletAddress }
        return "TrustedRouter account"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct AppConfig: Codable, Sendable, Hashable {
    public var defaultModel: String
    public var mode: AgentMode
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var trustedRouterAccount: TrustedRouterAccountProfile?
    public var favoriteModels: [String]

    private enum CodingKeys: String, CodingKey {
        case defaultModel
        case mode
        case apiBaseURL
        case authMode
        case developerOverrideEnabled
        case trustedRouterAccount
        case favoriteModels
    }

    public init(
        defaultModel: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        apiBaseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool = false,
        trustedRouterAccount: TrustedRouterAccountProfile? = nil,
        favoriteModels: [String] = []
    ) {
        self.defaultModel = TrustedRouterDefaults.normalizedDefaultModelID(defaultModel)
        self.mode = mode
        self.apiBaseURL = apiBaseURL
        self.authMode = developerOverrideEnabled ? .developerOverride : authMode
        self.developerOverrideEnabled = developerOverrideEnabled || authMode == .developerOverride
        self.trustedRouterAccount = trustedRouterAccount?.isEmpty == true ? nil : trustedRouterAccount
        self.favoriteModels = Self.normalizedModelIDs(favoriteModels)
    }

    public init(
        defaultModel: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        apiBaseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        developerOverrideEnabled: Bool
    ) {
        self.init(
            defaultModel: defaultModel,
            mode: mode,
            apiBaseURL: apiBaseURL,
            authMode: developerOverrideEnabled ? .developerOverride : .oauth,
            developerOverrideEnabled: developerOverrideEnabled,
            trustedRouterAccount: nil,
            favoriteModels: []
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            defaultModel: try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? TrustedRouterDefaults.defaultModel,
            mode: try container.decodeIfPresent(AgentMode.self, forKey: .mode) ?? .auto,
            apiBaseURL: try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? TrustedRouterDefaults.defaultAPIBaseURL,
            authMode: try container.decodeIfPresent(TrustedRouterAuthMode.self, forKey: .authMode) ?? .oauth,
            developerOverrideEnabled: try container.decodeIfPresent(Bool.self, forKey: .developerOverrideEnabled) ?? false,
            trustedRouterAccount: try container.decodeIfPresent(TrustedRouterAccountProfile.self, forKey: .trustedRouterAccount),
            favoriteModels: try container.decodeIfPresent([String].self, forKey: .favoriteModels) ?? []
        )
    }

    private static func normalizedModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = TrustedRouterDefaults.canonicalModelID(trimmed)
            guard !modelID.isEmpty, seen.insert(modelID).inserted else { continue }
            normalized.append(modelID)
        }
        return normalized
    }
}

public enum JSONHelpers {
    public static func encodePretty<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(string.utf8))
    }
}
