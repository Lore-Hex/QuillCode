import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence

typealias WorkspaceSubagentRunRecordSink = @Sendable (
    SubagentRunRecord,
    UUID
) async -> Void

/// Bridges a model-authored `host.subagents.run` call into the same durable scheduler used by the
/// explicit `/subagents` command. The generic agent loop remains scheduler-agnostic: this executor
/// owns child persistence and returns the parent thread snapshot containing compact run manifests.
struct WorkspaceSubagentRunToolExecutor: Sendable {
    let sessionFactory: WorkspaceAgentSendSessionFactory
    let threadStore: SubagentThreadStore?
    let approvalPayloadStore: SubagentApprovalPayloadStore?
    let schedulerOverride: WorkspaceSubagentScheduler?
    let recordSink: WorkspaceSubagentRunRecordSink?

    var executionOverride: AgentThreadToolExecutionOverride {
        { call, _, parentThread, onProgress in
            guard call.name == ToolDefinition.subagentsRun.name else { return nil }
            return await execute(call, parentThread: parentThread, onProgress: onProgress)
        }
    }

    private func execute(
        _ call: ToolCall,
        parentThread: ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async -> AgentThreadToolExecution {
        let request: WorkspaceSubagentRunRequest
        do {
            request = try WorkspaceSubagentRunToolRequestDecoder.decode(call)
        } catch {
            return AgentThreadToolExecution(
                thread: parentThread,
                result: ToolResult(ok: false, error: error.localizedDescription)
            )
        }

        let runID = UUID()
        let projection = WorkspaceSubagentParentProjection(parentThread)
        let scheduler = schedulerOverride ?? WorkspaceSubagentScheduler(
            detailedWorker: AgentWorkspaceSubagentWorker.scheduledWorker(
                sessionFactory: sessionFactory,
                parentThread: parentThread,
                threadStore: threadStore,
                approvalPayloadStore: approvalPayloadStore
            )
        )
        let result = await scheduler.run(
            request: request,
            runID: runID,
            state: { record in
                await recordSink?(record, parentThread.id)
                let snapshot = await projection.record(record)
                await onProgress?(snapshot)
            },
            spawn: { _, summary in
                WorkspaceSubagentSpawnDirectiveParser.parse(summary)
            }
        )
        // The scheduler always publishes its terminal record through `state` before returning.
        // Reuse that projection instead of persisting and publishing the same snapshot twice.
        let finalThread = await projection.snapshot()
        let output = WorkspaceSubagentRunToolOutput(result: result)
        let stdout = (try? JSONHelpers.encodePretty(output)) ?? result.summary
        return AgentThreadToolExecution(
            thread: finalThread,
            result: ToolResult(ok: true, stdout: stdout)
        )
    }
}

private actor WorkspaceSubagentParentProjection {
    private var thread: ChatThread

    init(_ thread: ChatThread) {
        self.thread = thread
    }

    func record(_ record: SubagentRunRecord) -> ChatThread {
        if let index = thread.subagentRuns.firstIndex(where: { $0.id == record.id }) {
            var next = record
            next.lastPublishedSummary = thread.subagentRuns[index].lastPublishedSummary
            thread.subagentRuns[index] = next
        } else {
            thread.subagentRuns.append(record)
        }
        thread.updatedAt = Date()
        return thread
    }

    func snapshot() -> ChatThread {
        thread
    }
}

private struct WorkspaceSubagentRunToolOutput: Codable, Sendable, Hashable {
    struct Worker: Codable, Sendable, Hashable {
        var name: String
        var role: String
        var status: SubagentStatus
        var summary: String?
    }

    var runID: UUID
    var summary: String
    var workers: [Worker]
    var awaitingApproval: Bool

    init(result: WorkspaceSubagentRunResult) {
        self.runID = result.record.id
        self.summary = result.summary
        self.workers = result.record.workers.map {
            Worker(name: $0.name, role: $0.role, status: $0.status, summary: $0.summary)
        }
        self.awaitingApproval = result.record.workers.contains { $0.status == .awaitingApproval }
    }
}
