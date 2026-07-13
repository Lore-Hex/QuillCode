import Foundation

public enum SubagentStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case queued
    case running
    case blocked
    case awaitingApproval
    case interrupted
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
        case .awaitingApproval:
            return "Needs approval"
        case .interrupted:
            return "Interrupted"
        case .completed:
            return "Done"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

/// A bounded, presentation-safe projection of a delegated worker's approval gate. Exact tool
/// arguments and the child thread remain in the private subagent session store.
public struct SubagentApprovalGate: Codable, Sendable, Hashable {
    public var runID: String
    public var requestID: String
    public var toolName: String
    public var reason: String

    public init(runID: String, requestID: String, toolName: String, reason: String) {
        self.runID = runID
        self.requestID = requestID
        self.toolName = toolName
        self.reason = reason
    }
}

public enum SubagentTranscriptEntryKind: String, Codable, Sendable, Hashable {
    case assistant
    case tool
    case approval
}

public struct SubagentTranscriptEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: SubagentTranscriptEntryKind
    public var title: String
    public var detail: String
    public var statusLabel: String

    public init(
        id: String,
        kind: SubagentTranscriptEntryKind,
        title: String,
        detail: String = "",
        statusLabel: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
    }
}

public struct SubagentProgressItem: Codable, Sendable, Hashable {
    /// Stable identity for a scheduler-owned worker. Model-authored progress updates may omit it,
    /// preserving compatibility with the original public tool schema; only identified workers can
    /// expose a durable transcript drilldown.
    public var workerID: String?
    public var name: String
    public var role: String
    public var status: SubagentStatus
    public var summary: String?
    public var groupPath: [String]
    public var transcript: [SubagentTranscriptEntry]
    public var approvalGate: SubagentApprovalGate?

    public init(
        workerID: String? = nil,
        name: String,
        role: String,
        status: SubagentStatus,
        summary: String? = nil,
        transcript: [SubagentTranscriptEntry] = [],
        approvalGate: SubagentApprovalGate? = nil
    ) {
        self.init(
            workerID: workerID,
            name: name,
            role: role,
            status: status,
            summary: summary,
            groupPath: [],
            transcript: transcript,
            approvalGate: approvalGate
        )
    }

    public init(
        workerID: String? = nil,
        name: String,
        role: String,
        status: SubagentStatus,
        summary: String? = nil,
        groupPath: [String],
        transcript: [SubagentTranscriptEntry] = [],
        approvalGate: SubagentApprovalGate? = nil
    ) {
        self.workerID = workerID
        self.name = name
        self.role = role
        self.status = status
        self.summary = summary
        self.groupPath = groupPath
        self.transcript = transcript
        self.approvalGate = approvalGate
    }

    private enum CodingKeys: String, CodingKey {
        case workerID
        case name
        case groupPath
        case role
        case status
        case summary
        case transcript
        case approvalGate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workerID = try container.decodeIfPresent(String.self, forKey: .workerID)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(String.self, forKey: .role)
        status = try container.decode(SubagentStatus.self, forKey: .status)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        groupPath = try container.decodeIfPresent([String].self, forKey: .groupPath) ?? []
        transcript = try container.decodeIfPresent([SubagentTranscriptEntry].self, forKey: .transcript) ?? []
        approvalGate = try container.decodeIfPresent(SubagentApprovalGate.self, forKey: .approvalGate)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(workerID, forKey: .workerID)
        try container.encode(name, forKey: .name)
        if !groupPath.isEmpty {
            try container.encode(groupPath, forKey: .groupPath)
        }
        try container.encode(role, forKey: .role)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(summary, forKey: .summary)
        if !transcript.isEmpty {
            try container.encode(transcript, forKey: .transcript)
        }
        try container.encodeIfPresent(approvalGate, forKey: .approvalGate)
    }
}

/// Durable progress through the approval state machine. A completed or denied approval is removed
/// from its worker record after the scheduler has checkpointed the resulting child transcript.
public enum SubagentApprovalPhase: String, Codable, Sendable, Hashable, CaseIterable {
    case pending
    case decisionRecorded
    case executing
}

/// Compact approval metadata persisted with the parent thread. The raw tool call is deliberately
/// addressed by an opaque key and stored separately with owner-only filesystem permissions.
public struct SubagentPendingApproval: Codable, Sendable, Hashable {
    public var requestID: String
    public var generation: Int
    public var payloadKey: UUID
    public var createdAt: Date
    public var phase: SubagentApprovalPhase

    public init(
        requestID: String,
        generation: Int = 0,
        payloadKey: UUID = UUID(),
        createdAt: Date = Date(),
        phase: SubagentApprovalPhase = .pending
    ) {
        self.requestID = requestID
        self.generation = generation
        self.payloadKey = payloadKey
        self.createdAt = createdAt
        self.phase = phase
    }
}

/// Durable scheduler state for one worker. Its transcript lives in the hidden child-thread store
/// under `childThreadID`; only compact metadata is kept in the parent thread.
public struct SubagentWorkerRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var childThreadID: UUID
    public var dependencyIDs: [String]
    public var name: String
    public var role: String
    public var groupPath: [String]
    public var depth: Int
    public var attempt: Int
    public var status: SubagentStatus
    public var summary: String?
    public var pendingApproval: SubagentPendingApproval?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        childThreadID: UUID = UUID(),
        dependencyIDs: [String] = [],
        name: String,
        role: String,
        groupPath: [String] = [],
        depth: Int = 0,
        attempt: Int = 1,
        status: SubagentStatus = .queued,
        summary: String? = nil,
        pendingApproval: SubagentPendingApproval? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.childThreadID = childThreadID
        self.dependencyIDs = dependencyIDs
        self.name = name
        self.role = role
        self.groupPath = groupPath
        self.depth = depth
        self.attempt = attempt
        self.status = status
        self.summary = summary
        self.pendingApproval = pendingApproval
        self.updatedAt = updatedAt
    }
}

/// A compact, restart-safe manifest for one delegated run. Child transcripts and raw held tool
/// calls are stored separately so ordinary parent-thread loads remain small and safe to inspect.
public struct SubagentRunRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var objective: String
    public var maxConcurrentWorkers: Int?
    public var maxDepth: Int
    public var maxTotalJobs: Int
    public var workers: [SubagentWorkerRecord]
    public var lastPublishedSummary: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(),
        objective: String,
        maxConcurrentWorkers: Int? = nil,
        maxDepth: Int = 3,
        maxTotalJobs: Int = 64,
        workers: [SubagentWorkerRecord] = [],
        lastPublishedSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.objective = objective
        self.maxConcurrentWorkers = maxConcurrentWorkers
        self.maxDepth = maxDepth
        self.maxTotalJobs = maxTotalJobs
        self.workers = workers
        self.lastPublishedSummary = lastPublishedSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
    }

    public func worker(id: String) -> SubagentWorkerRecord? {
        workers.first { $0.id == id }
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
