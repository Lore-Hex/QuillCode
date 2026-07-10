import Foundation

public enum ThreadGoalStatus: String, Codable, Sendable, Hashable {
    case active
    case blocked
    case completed
}

/// One durable objective attached to a chat. Goals live with the thread so they survive relaunch,
/// compaction, forks, and project switches without becoming ordinary transcript text.
public struct ThreadGoal: Codable, Sendable, Hashable {
    public static let maximumObjectiveLength = 4_000
    public static let maximumBlockerLength = 1_000

    public var objective: String
    public var status: ThreadGoalStatus
    public var blocker: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init?(
        objective: String,
        status: ThreadGoalStatus = .active,
        blocker: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        guard let objective = Self.normalized(objective, maximumLength: Self.maximumObjectiveLength) else {
            return nil
        }
        self.objective = objective
        self.status = status
        self.blocker = status == .blocked
            ? Self.normalized(blocker, maximumLength: Self.maximumBlockerLength)
            : nil
        self.createdAt = createdAt
        self.updatedAt = max(createdAt, updatedAt)
    }

    public func updating(
        status: ThreadGoalStatus,
        blocker: String? = nil,
        at date: Date = Date()
    ) -> ThreadGoal {
        ThreadGoal(
            objective: objective,
            status: status,
            blocker: blocker,
            createdAt: createdAt,
            updatedAt: date
        ) ?? self
    }

    private enum CodingKeys: String, CodingKey {
        case objective
        case status
        case blocker
        case createdAt
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let objective = try container.decode(String.self, forKey: .objective)
        let status = try container.decode(ThreadGoalStatus.self, forKey: .status)
        let blocker = try container.decodeIfPresent(String.self, forKey: .blocker)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        guard let goal = ThreadGoal(
            objective: objective,
            status: status,
            blocker: blocker,
            createdAt: createdAt,
            updatedAt: updatedAt
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .objective,
                in: container,
                debugDescription: "A thread goal must have a non-empty objective."
            )
        }
        self = goal
    }

    private static func normalized(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}
