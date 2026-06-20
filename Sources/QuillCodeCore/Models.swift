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
    case notice
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

public struct ProjectRef: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String
    public var instructions: [ProjectInstruction]
    public var localActions: [LocalEnvironmentAction]
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastOpenedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        localActions: [LocalEnvironmentAction] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.instructions = instructions
        self.localActions = localActions
        self.lastOpenedAt = lastOpenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case instructions
        case localActions
        case lastOpenedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.instructions = try container.decodeIfPresent([ProjectInstruction].self, forKey: .instructions) ?? []
        self.localActions = try container.decodeIfPresent([LocalEnvironmentAction].self, forKey: .localActions) ?? []
        self.lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(localActions, forKey: .localActions)
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

public struct ChatThread: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var projectID: UUID?
    public var instructions: [ProjectInstruction]
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
        instructions: [ProjectInstruction] = []
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.instructions = instructions
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
    public static let safetyPrimaryModel = "glm-5.2"
    public static let safetyFallbackModel = "kimi-k2.6"
}

public struct AppConfig: Codable, Sendable, Hashable {
    public var defaultModel: String
    public var mode: AgentMode
    public var apiBaseURL: String
    public var developerOverrideEnabled: Bool

    public init(
        defaultModel: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        apiBaseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        developerOverrideEnabled: Bool = false
    ) {
        self.defaultModel = defaultModel
        self.mode = mode
        self.apiBaseURL = apiBaseURL
        self.developerOverrideEnabled = developerOverrideEnabled
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
