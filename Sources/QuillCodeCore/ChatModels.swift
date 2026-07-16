import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Structured user-selected context that accompanies a visible chat message.
///
/// The visible message remains in `ChatMessage.content`; these references let protocol clients
/// round-trip explicit skill and app/plugin selections without leaking loaded skill instructions
/// into the transcript UI. `context` is an immutable, bounded snapshot used for model history so a
/// later edit to the source skill cannot rewrite an earlier turn.
public struct ChatInputReference: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case skill
        case mention
    }

    public static let maximumCountPerMessage = 16

    public var kind: Kind
    public var name: String
    public var path: String
    public var context: String?

    public init(kind: Kind, name: String, path: String, context: String? = nil) {
        self.kind = kind
        self.name = name
        self.path = path
        self.context = context
    }
}

public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var role: ChatRole
    public var content: String
    public var attachments: [ChatAttachment]
    /// Explicit skill or app/plugin selections attached to this message. Ordinary desktop messages
    /// leave this empty; protocol-backed clients can persist and replay the richer input exactly.
    public var inputReferences: [ChatInputReference]
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
        inputReferences: [ChatInputReference] = [],
        turnID: String? = nil,
        clientMessageID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = Array(attachments.prefix(ChatAttachment.maximumCountPerTurn))
        self.inputReferences = Array(inputReferences.prefix(ChatInputReference.maximumCountPerMessage))
        self.turnID = turnID
        self.clientMessageID = clientMessageID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case inputReferences
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
        self.inputReferences = Array(
            (try container.decodeIfPresent([ChatInputReference].self, forKey: .inputReferences) ?? [])
                .prefix(ChatInputReference.maximumCountPerMessage)
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
        try container.encode(inputReferences, forKey: .inputReferences)
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
