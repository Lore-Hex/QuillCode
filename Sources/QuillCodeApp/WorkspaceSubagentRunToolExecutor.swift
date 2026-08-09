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
                guard let snapshot = await projection.recordIfOpen(record) else { return }
                await recordSink?(record, parentThread.id)
                guard await projection.isOpen else { return }
                await onProgress?(snapshot)
            },
            deadline: { parentCancelled in
                let result = await projection.finalizeAtDeadline(
                    request: request,
                    runID: runID,
                    threadStore: threadStore,
                    parentCancelled: parentCancelled
                )
                await recordSink?(result.record, parentThread.id)
                await onProgress?(await projection.snapshot())
                return result
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
        deadline: @escaping @Sendable (Bool) async -> WorkspaceSubagentRunResult,
        spawn: @escaping WorkspaceSubagentScheduler.Spawner
    ) async -> WorkspaceSubagentBoundedRun {
        let (events, continuation) = AsyncStream<WorkspaceSubagentRunRace>.makeStream()
        let schedulerTask = Task {
            let result = await scheduler.run(
                request: request,
                runID: runID,
                state: state,
                spawn: spawn
            )
            continuation.yield(.result(result))
        }
        let deadlineTask = Task {
            do {
                try await Task.sleep(for: delegationBudget)
                continuation.yield(.delegationBudgetReached)
            } catch is CancellationError {
                continuation.yield(.parentCancelled)
            }
        }

        var iterator = events.makeAsyncIterator()
        let outcome = await withTaskCancellationHandler {
            await iterator.next()
        } onCancel: {
            schedulerTask.cancel()
            deadlineTask.cancel()
        }
        continuation.finish()

        switch outcome {
        case .result(let result):
            deadlineTask.cancel()
            return WorkspaceSubagentBoundedRun(result: result, delegationBudgetReached: false)
        case .delegationBudgetReached:
            schedulerTask.cancel()
            return WorkspaceSubagentBoundedRun(
                result: await deadline(false),
                delegationBudgetReached: true
            )
        case .parentCancelled:
            schedulerTask.cancel()
            return WorkspaceSubagentBoundedRun(
                result: await deadline(true),
                delegationBudgetReached: false
            )
        case nil:
            schedulerTask.cancel()
            deadlineTask.cancel()
            return WorkspaceSubagentBoundedRun(
                result: await deadline(Task.isCancelled),
                delegationBudgetReached: !Task.isCancelled
            )
        }
    }
}

private enum WorkspaceSubagentRunRace: Sendable {
    case result(WorkspaceSubagentRunResult)
    case delegationBudgetReached
    case parentCancelled
}

private struct WorkspaceSubagentBoundedRun: Sendable {
    var result: WorkspaceSubagentRunResult
    var delegationBudgetReached: Bool
}

private actor WorkspaceSubagentParentProjection {
    private var thread: ChatThread
    private(set) var isOpen = true

    init(_ thread: ChatThread) {
        self.thread = thread
    }

    func recordIfOpen(_ record: SubagentRunRecord) -> ChatThread? {
        guard isOpen else { return nil }
        apply(record)
        return thread
    }

    func finalizeAtDeadline(
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        threadStore: SubagentThreadStore?,
        parentCancelled: Bool
    ) -> WorkspaceSubagentRunResult {
        isOpen = false
        let now = Date()
        var record = thread.subagentRuns.first(where: { $0.id == runID })
            ?? Self.initialRecord(request: request, runID: runID, now: now)
        var items: [SubagentProgressItem] = []
        var workerResults: [String: String] = [:]

        for index in record.workers.indices {
            var worker = record.workers[index]
            let childThread = try? threadStore?.load(worker.childThreadID)
            let transcript = childThread.map(WorkspaceSubagentTranscriptBuilder.entries(from:)) ?? []
            let fullSummary: String

            switch worker.status {
            case .queued, .running, .blocked, .interrupted:
                worker.status = .cancelled
                worker.pendingApproval = nil
                fullSummary = childThread.map(AgentWorkspaceSubagentWorker.cancellationSummary(from:))
                    ?? (parentCancelled
                        ? "Cancelled when the parent run stopped before this worker returned."
                        : "Cancelled at the hard delegation deadline before this worker returned.")
            case .completed, .failed, .cancelled, .awaitingApproval:
                fullSummary = Self.recoveredSummary(for: worker, childThread: childThread)
            }

            worker.summary = WorkspaceSubagentScheduler.boundedSummary(fullSummary)
            worker.updatedAt = now
            record.workers[index] = worker
            workerResults[worker.id] = fullSummary
            items.append(SubagentProgressItem(
                workerID: worker.id,
                name: worker.name,
                role: worker.role,
                status: worker.status,
                summary: worker.summary,
                groupPath: worker.groupPath,
                transcript: transcript
            ))
        }

        record.updatedAt = now
        record.finishedAt = record.workers.allSatisfy {
            $0.status == .completed || $0.status == .failed || $0.status == .cancelled
        } ? now : nil
        apply(record)
        let update = SubagentProgressUpdate(objective: request.objective, subagents: items)
        return WorkspaceSubagentRunResult(
            update: update,
            summary: WorkspaceSubagentScheduler.finalSummary(
                objective: request.objective,
                items: items
            ),
            record: record,
            workerResults: workerResults
        )
    }

    private func apply(_ record: SubagentRunRecord) {
        if let index = thread.subagentRuns.firstIndex(where: { $0.id == record.id }) {
            var next = record
            next.lastPublishedSummary = thread.subagentRuns[index].lastPublishedSummary
            thread.subagentRuns[index] = next
        } else {
            thread.subagentRuns.append(record)
        }
        thread.updatedAt = Date()
    }

    func snapshot() -> ChatThread {
        thread
    }

    private static func initialRecord(
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        now: Date
    ) -> SubagentRunRecord {
        var workers = request.workers.map { request in
            SubagentWorkerRecord(
                name: request.name,
                role: request.role,
                groupPath: request.groupPath,
                status: .queued,
                updatedAt: now
            )
        }
        let idByName = Dictionary(uniqueKeysWithValues: workers.map { ($0.name.lowercased(), $0.id) })
        for index in workers.indices {
            workers[index].dependencyIDs = request.workers[index].dependsOn.compactMap {
                idByName[$0.lowercased()]
            }
        }
        return SubagentRunRecord(
            id: runID,
            objective: request.objective,
            maxConcurrentWorkers: request.maxConcurrentWorkers,
            workers: workers,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func recoveredSummary(
        for worker: SubagentWorkerRecord,
        childThread: ChatThread?
    ) -> String {
        guard let childThread else {
            return worker.summary ?? worker.status.label
        }
        if worker.status == .cancelled {
            return AgentWorkspaceSubagentWorker.cancellationSummary(from: childThread)
        }
        if worker.status == .awaitingApproval {
            return worker.summary ?? "Worker needs approval."
        }
        let answer = childThread.messages
            .last(where: { $0.role == .assistant })
            .flatMap { WorkspaceContextSummarySanitizer.summary(from: $0.content) }
        guard worker.status == .failed,
              let evidence = WorkspaceSubagentEvidenceDigest.summary(from: childThread),
              !evidence.isEmpty
        else {
            return answer ?? worker.summary ?? worker.status.label
        }
        return "\(answer ?? worker.summary ?? worker.status.label)\n\nRecovered grounded evidence:\n\(evidence)"
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
