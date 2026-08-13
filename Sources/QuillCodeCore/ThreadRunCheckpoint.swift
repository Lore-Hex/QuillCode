import Foundation

/// Privacy-safe durable ownership for one in-flight parent-chat run.
///
/// The checkpoint intentionally stores no prompt, path, model response, or tool arguments. Array
/// boundaries let relaunch recovery distinguish a completed answer or durable approval gate from
/// work that disappeared with the previous process.
public struct ThreadRunCheckpoint: Codable, Sendable, Hashable {
    public static let schemaVersion = 1

    public var id: UUID
    public var startedAt: Date
    public var messageCountAtStart: Int
    public var eventCountAtStart: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        messageCountAtStart: Int,
        eventCountAtStart: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.messageCountAtStart = max(0, messageCountAtStart)
        self.eventCountAtStart = max(0, eventCountAtStart)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case startedAt
        case messageCountAtStart
        case eventCountAtStart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.messageCountAtStart = max(
            0,
            try container.decode(Int.self, forKey: .messageCountAtStart)
        )
        self.eventCountAtStart = max(
            0,
            try container.decode(Int.self, forKey: .eventCountAtStart)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(messageCountAtStart, forKey: .messageCountAtStart)
        try container.encode(eventCountAtStart, forKey: .eventCountAtStart)
    }
}
