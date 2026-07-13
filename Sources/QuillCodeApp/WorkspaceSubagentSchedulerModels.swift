import Foundation
import QuillCodeAgent
import QuillCodeCore

struct WorkspaceSubagentPriorResult: Codable, Sendable, Hashable {
    var name: String
    var summary: String

    init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

struct WorkspaceSubagentJob: Codable, Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var role: String
    var objective: String
    var dependsOn: [String]
    var groupPath: [String]
    var priorResults: [WorkspaceSubagentPriorResult]
    /// Delegation depth: top-level workers are 0; a child spawned by a worker is its parent's
    /// depth + 1. The scheduler refuses to spawn past `maxDepth`, which guarantees termination.
    var depth: Int

    init(
        name: String,
        role: String,
        objective: String = "",
        dependsOn: [String] = [],
        groupPath: [String] = [],
        priorResults: [WorkspaceSubagentPriorResult] = [],
        depth: Int = 0
    ) {
        self.name = name
        self.role = role
        self.objective = objective
        self.dependsOn = dependsOn
        self.groupPath = groupPath
        self.priorResults = priorResults
        self.depth = depth
    }
}

struct WorkspaceSubagentRunResult: Sendable, Hashable {
    var update: SubagentProgressUpdate
    var summary: String
    var state: WorkspaceSubagentRunState

    var isPaused: Bool { !state.pausedWorkers.isEmpty }
}

struct WorkspaceSubagentApprovalPause: Codable, Error, Sendable, Hashable {
    var prompt: String
    var thread: ChatThread
    var pendingApproval: AgentPendingApproval
}

struct WorkspaceSubagentRunState: Codable, Sendable, Hashable {
    var id: String
    var objective: String
    var maxConcurrentWorkers: Int?
    var jobs: [WorkspaceSubagentJob]
    var items: [SubagentProgressItem]
    var pausedWorkers: [String: WorkspaceSubagentApprovalPause]

    init(
        id: String = UUID().uuidString,
        objective: String,
        maxConcurrentWorkers: Int?,
        jobs: [WorkspaceSubagentJob],
        items: [SubagentProgressItem],
        pausedWorkers: [String: WorkspaceSubagentApprovalPause] = [:]
    ) {
        self.id = id
        self.objective = objective
        self.maxConcurrentWorkers = maxConcurrentWorkers
        self.jobs = jobs
        self.items = items
        self.pausedWorkers = pausedWorkers
    }
}

struct WorkspaceSubagentWorkerResult: Sendable, Hashable {
    var summary: String
    var transcript: [SubagentTranscriptEntry]

    init(summary: String, transcript: [SubagentTranscriptEntry] = []) {
        self.summary = summary
        self.transcript = transcript
    }
}
