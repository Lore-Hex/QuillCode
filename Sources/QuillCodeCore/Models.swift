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

public struct ProjectRef: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var instructions: [ProjectInstruction]
    public var localActions: [LocalEnvironmentAction]
    public var extensionManifests: [ProjectExtensionManifest]
    public var memories: [MemoryNote]
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        localActions: [LocalEnvironmentAction] = [],
        extensionManifests: [ProjectExtensionManifest],
        memories: [MemoryNote] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
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
        try container.encode(instructions, forKey: .instructions)
        try container.encode(localActions, forKey: .localActions)
        try container.encode(extensionManifests, forKey: .extensionManifests)
        try container.encode(memories, forKey: .memories)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
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
    public var relativePath: String
    public var command: String

    public init(id: String, title: String, relativePath: String, command: String) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.command = command
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
        self.model = try container.decode(String.self, forKey: .model)
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

public enum TrustedRouterDefaults {
    public static let defaultModel = "trustedrouter/fusion"
    public static let defaultAPIBaseURL = "https://api.quillrouter.com/v1"
    public static let signInURL = "https://trustedrouter.com/sign-in-with-trustedrouter"
    public static let loopbackCallbackURL = "http://localhost:3000/callback"
    public static let safetyPrimaryModel = "glm-5.2"
    public static let safetyFallbackModel = "kimi-k2.6"
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
        self.defaultModel = defaultModel
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
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            normalized.append(trimmed)
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
