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

/// Stable scheduler identity plus the presentation fields required to build a delegated prompt.
/// Custom decoding keeps the short-lived name-keyed session format readable during migration.
struct WorkspaceSubagentJob: Codable, Sendable, Hashable, Identifiable {
    var runID: UUID
    var id: String
    var childThreadID: UUID
    var name: String
    var role: String
    var objective: String
    var dependsOn: [String]
    var dependencyIDs: [String]
    var groupPath: [String]
    var priorResults: [WorkspaceSubagentPriorResult]
    var attempt: Int
    /// Top-level workers are depth 0. The scheduler rejects children beyond its depth limit.
    var depth: Int

    init(
        runID: UUID = UUID(),
        id: String = UUID().uuidString,
        childThreadID: UUID = UUID(),
        name: String,
        role: String,
        objective: String = "",
        dependsOn: [String] = [],
        dependencyIDs: [String] = [],
        groupPath: [String] = [],
        priorResults: [WorkspaceSubagentPriorResult] = [],
        attempt: Int = 1,
        depth: Int = 0
    ) {
        self.runID = runID
        self.id = id
        self.childThreadID = childThreadID
        self.name = name
        self.role = role
        self.objective = objective
        self.dependsOn = dependsOn
        self.dependencyIDs = dependencyIDs
        self.groupPath = groupPath
        self.priorResults = priorResults
        self.attempt = max(1, attempt)
        self.depth = max(0, depth)
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case id
        case childThreadID
        case name
        case role
        case objective
        case dependsOn
        case dependencyIDs
        case groupPath
        case priorResults
        case attempt
        case depth
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        self.init(
            runID: try container.decodeIfPresent(UUID.self, forKey: .runID) ?? UUID(),
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? name,
            childThreadID: try container.decodeIfPresent(UUID.self, forKey: .childThreadID) ?? UUID(),
            name: name,
            role: try container.decode(String.self, forKey: .role),
            objective: try container.decodeIfPresent(String.self, forKey: .objective) ?? "",
            dependsOn: try container.decodeIfPresent([String].self, forKey: .dependsOn) ?? [],
            dependencyIDs: try container.decodeIfPresent([String].self, forKey: .dependencyIDs) ?? [],
            groupPath: try container.decodeIfPresent([String].self, forKey: .groupPath) ?? [],
            priorResults: try container.decodeIfPresent(
                [WorkspaceSubagentPriorResult].self,
                forKey: .priorResults
            ) ?? [],
            attempt: try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 1,
            depth: try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        )
    }
}

/// Legacy whole-session continuation retained only to migrate runs created by the first durable
/// approval implementation. New runs persist compact manifests, child transcripts, and raw calls
/// in separate stores.
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
    var status: SubagentStatus
    var summary: String
    var pendingApproval: SubagentPendingApproval?
    var transcript: [SubagentTranscriptEntry]

    init(
        status: SubagentStatus = .completed,
        summary: String,
        pendingApproval: SubagentPendingApproval? = nil,
        transcript: [SubagentTranscriptEntry] = []
    ) {
        self.status = status
        self.summary = summary
        self.pendingApproval = pendingApproval
        self.transcript = transcript
    }
}

struct WorkspaceSubagentRunResult: Sendable, Hashable {
    var update: SubagentProgressUpdate
    var summary: String
    var record: SubagentRunRecord
    private var legacyState: WorkspaceSubagentRunState?

    var state: WorkspaceSubagentRunState {
        legacyState ?? WorkspaceSubagentRunState(record: record, update: update)
    }

    var isPaused: Bool {
        legacyState?.pausedWorkers.isEmpty == false
            || record.workers.contains { $0.status == .awaitingApproval }
    }

    init(
        update: SubagentProgressUpdate,
        summary: String,
        record: SubagentRunRecord,
        legacyState: WorkspaceSubagentRunState? = nil
    ) {
        self.update = update
        self.summary = summary
        self.record = record
        self.legacyState = legacyState
    }
}

private extension WorkspaceSubagentRunState {
    init(record: SubagentRunRecord, update: SubagentProgressUpdate) {
        let nameByID = Dictionary(uniqueKeysWithValues: record.workers.map { ($0.id, $0.name) })
        self.init(
            id: record.id.uuidString,
            objective: record.objective,
            maxConcurrentWorkers: record.maxConcurrentWorkers,
            jobs: record.workers.map { worker in
                WorkspaceSubagentJob(
                    runID: record.id,
                    id: worker.id,
                    childThreadID: worker.childThreadID,
                    name: worker.name,
                    role: worker.role,
                    objective: record.objective,
                    dependsOn: worker.dependencyIDs.compactMap { nameByID[$0] },
                    dependencyIDs: worker.dependencyIDs,
                    groupPath: worker.groupPath,
                    attempt: worker.attempt,
                    depth: worker.depth
                )
            },
            items: update.subagents
        )
    }
}
