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
    static let defaultDelegationBudget: Duration = .seconds(600)

    let sessionFactory: WorkspaceAgentSendSessionFactory
    let threadStore: SubagentThreadStore?
    let approvalPayloadStore: SubagentApprovalPayloadStore?
    let schedulerOverride: WorkspaceSubagentScheduler?
    let recordSink: WorkspaceSubagentRunRecordSink?
    let delegationBudget: Duration

    init(
        sessionFactory: WorkspaceAgentSendSessionFactory,
        threadStore: SubagentThreadStore?,
        approvalPayloadStore: SubagentApprovalPayloadStore?,
        schedulerOverride: WorkspaceSubagentScheduler?,
        recordSink: WorkspaceSubagentRunRecordSink?,
        delegationBudget: Duration = Self.defaultDelegationBudget
    ) {
        self.sessionFactory = sessionFactory
        self.threadStore = threadStore
        self.approvalPayloadStore = approvalPayloadStore
        self.schedulerOverride = schedulerOverride
        self.recordSink = recordSink
        self.delegationBudget = delegationBudget
    }

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
        let boundedRun = await run(
            scheduler: scheduler,
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
        let result = boundedRun.result
        // The scheduler always publishes its terminal record through `state` before returning.
        // Reuse that projection instead of persisting and publishing the same snapshot twice.
        let finalThread = await projection.snapshot()
        let output = WorkspaceSubagentRunToolOutput(
            result: result,
            delegationBudgetReached: boundedRun.delegationBudgetReached
        )
        let stdout = (try? JSONHelpers.encodePretty(output)) ?? result.summary
        return AgentThreadToolExecution(
            thread: finalThread,
            result: ToolResult(ok: true, stdout: stdout)
        )
    }

    private func run(
        scheduler: WorkspaceSubagentScheduler,
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        state: @escaping WorkspaceSubagentScheduler.StateSink,
        spawn: @escaping WorkspaceSubagentScheduler.Spawner
    ) async -> WorkspaceSubagentBoundedRun {
        await withTaskGroup(of: WorkspaceSubagentRunRace.self) { group in
            group.addTask {
                .result(await scheduler.run(
                    request: request,
                    runID: runID,
                    state: state,
                    spawn: spawn
                ))
            }
            group.addTask {
                do {
                    try await Task.sleep(for: delegationBudget)
                    return .delegationBudgetReached
                } catch {
                    return .cancelledDeadline
                }
            }

            var delegationBudgetReached = false
            while let outcome = await group.next() {
                switch outcome {
                case .result(let result):
                    group.cancelAll()
                    return WorkspaceSubagentBoundedRun(
                        result: result,
                        delegationBudgetReached: delegationBudgetReached
                    )
                case .delegationBudgetReached:
                    delegationBudgetReached = true
                    group.cancelAll()
                case .cancelledDeadline:
                    continue
                }
            }
            preconditionFailure("Subagent scheduler ended without a result")
        }
    }
}

private enum WorkspaceSubagentRunRace: Sendable {
    case result(WorkspaceSubagentRunResult)
    case delegationBudgetReached
    case cancelledDeadline
}

private struct WorkspaceSubagentBoundedRun: Sendable {
    var result: WorkspaceSubagentRunResult
    var delegationBudgetReached: Bool
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
    private static let parentSummaryLimit = 6_000

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

    init(result: WorkspaceSubagentRunResult, delegationBudgetReached: Bool = false) {
        self.runID = result.record.id
        self.workers = result.record.workers.map { worker in
            Worker(
                name: worker.name,
                role: worker.role,
                status: worker.status,
                summary: result.workerResults[worker.id] ?? worker.summary
            )
        }
        let detailedResults = workers.compactMap { worker -> String? in
            guard let summary = worker.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summary.isEmpty
            else { return nil }
            let bounded = String(summary.prefix(Self.parentSummaryLimit))
            return "## \(worker.name) (\(worker.status.label))\n\(bounded)"
        }
        let synthesisDirective = delegationBudgetReached
            ? "Delegation time budget reached. Do not start more research. Synthesize the parent deliverable now from the completed results and existing evidence."
            : nil
        self.summary = ([synthesisDirective, result.summary] + detailedResults)
            .compactMap { $0 }
            .joined(separator: "\n\n")
        self.awaitingApproval = result.record.workers.contains { $0.status == .awaitingApproval }
    }
}
