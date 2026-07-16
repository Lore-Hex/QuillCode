import Foundation

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
    public var attachments: [ChatAttachment]
    /// Stable protocol turn identity when the message originated from a multi-message turn.
    /// Ordinary desktop messages leave this nil and continue to use their own id as a boundary.
    public var turnID: String?
    /// Optional caller-provided identity for a user message (for example app-server
    /// `clientUserMessageId`). It is metadata only and never enters model context.
    public var clientMessageID: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachments: [ChatAttachment] = [],
        turnID: String? = nil,
        clientMessageID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = Array(attachments.prefix(ChatAttachment.maximumCountPerTurn))
        self.turnID = turnID
        self.clientMessageID = clientMessageID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case turnID
        case clientMessageID
        case createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(ChatRole.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.attachments = Array(
            (try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? [])
                .prefix(ChatAttachment.maximumCountPerTurn)
        )
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        self.clientMessageID = try container.decodeIfPresent(String.self, forKey: .clientMessageID)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(turnID, forKey: .turnID)
        try container.encodeIfPresent(clientMessageID, forKey: .clientMessageID)
        try container.encode(createdAt, forKey: .createdAt)
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
