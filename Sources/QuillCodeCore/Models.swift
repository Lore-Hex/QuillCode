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
    public var recommendedVerdict: ApprovalVerdict?

    public init(
        id: String = "approval-\(UUID().uuidString)",
        toolCall: ToolCall,
        toolDefinition: ToolDefinition?,
        reason: String,
        recommendedVerdict: ApprovalVerdict? = nil
    ) {
        self.id = id
        self.toolCall = toolCall
        self.toolDefinition = toolDefinition
        self.reason = reason
        self.recommendedVerdict = recommendedVerdict
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
        self.model = TrustedRouterDefaults.normalizedDefaultModelID(model)
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
