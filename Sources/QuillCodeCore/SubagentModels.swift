public enum SubagentStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case queued
    case running
    case blocked
    case completed
    case cancelled
    case failed

    public var label: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .blocked:
            return "Blocked"
        case .completed:
            return "Done"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

public struct SubagentProgressItem: Codable, Sendable, Hashable {
    public var name: String
    public var role: String
    public var status: SubagentStatus
    public var summary: String?
    public var groupPath: [String]

    public init(name: String, role: String, status: SubagentStatus, summary: String? = nil) {
        self.init(name: name, role: role, status: status, summary: summary, groupPath: [])
    }

    public init(name: String, role: String, status: SubagentStatus, summary: String? = nil, groupPath: [String]) {
        self.name = name
        self.role = role
        self.status = status
        self.summary = summary
        self.groupPath = groupPath
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case groupPath
        case role
        case status
        case summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(String.self, forKey: .role)
        status = try container.decode(SubagentStatus.self, forKey: .status)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        groupPath = try container.decodeIfPresent([String].self, forKey: .groupPath) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if !groupPath.isEmpty {
            try container.encode(groupPath, forKey: .groupPath)
        }
        try container.encode(role, forKey: .role)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

public struct SubagentProgressUpdate: Codable, Sendable, Hashable {
    public var objective: String?
    public var subagents: [SubagentProgressItem]

    public init(objective: String? = nil, subagents: [SubagentProgressItem]) {
        self.objective = objective
        self.subagents = subagents
    }
}
