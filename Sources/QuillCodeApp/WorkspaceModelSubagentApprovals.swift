import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
public extension QuillCodeWorkspaceModel {
    /// Records a refusal synchronously so it cannot be dropped behind another send. Graph cleanup
    /// is intentionally separate and may be serialized through the desktop task coordinator.
    @discardableResult
    func recordSubagentDenial(_ action: ToolCardActionSurface) -> Bool {
        guard action.kind == .deny else {
            setLastError("The delegated refusal is no longer available.")
            return false
        }
        do {
            let context = try prepareSubagentDecision(action)
            try finishSubagentDenial(context)
            setLastError(nil)
            return true
        } catch {
            interruptSubagentApproval(action.subagentTarget)
            setLastError(error.localizedDescription)
            return false
        }
    }

    /// Continues the dependency graph after a refusal has already been durably recorded.
    @discardableResult
    func resumeSubagentRunAfterDecision(
        _ target: WorkspaceSubagentApprovalTarget,
        workspaceRoot: URL
    ) async -> Bool {
        do {
            let record = try subagentRun(parentThreadID: target.parentThreadID, runID: target.runID)
            guard let worker = record.workers.first(where: { $0.id == target.workerID }),
                  worker.status == .cancelled,
                  worker.pendingApproval == nil
            else {
                throw WorkspaceSubagentApprovalError.staleApproval
            }
            return await resumeSubagentRun(
                record,
                parentThreadID: target.parentThreadID,
                workspaceRoot: workspaceRoot,
                spawnFromWorkerIDs: []
            )
        } catch {
            setLastError(error.localizedDescription)
            return false
        }
    }

    /// Resolves one delegated approval against the exact persisted parent/run/worker generation.
    /// The selected sidebar thread is deliberately irrelevant: a user may inspect another chat
    /// while this transaction executes without redirecting the held tool or graph continuation.
    @discardableResult
    func approveSubagentToolCardAndResume(
        _ action: ToolCardActionSurface,
        workspaceRoot: URL
    ) async -> Bool {
        guard let target = action.subagentTarget,
              action.kind == .approve || action.kind == .deny
        else {
            setLastError("The delegated approval is no longer available.")
            return false
        }

        if action.kind == .deny {
            guard recordSubagentDenial(action) else { return false }
            return await resumeSubagentRunAfterDecision(target, workspaceRoot: workspaceRoot)
        }

        do {
            let context = try prepareSubagentDecision(action)
            return try await executeSubagentApproval(
                context,
                workspaceRoot: workspaceRoot
            )
        } catch is CancellationError {
            interruptSubagentApproval(action.subagentTarget)
            return false
        } catch {
            interruptSubagentApproval(action.subagentTarget)
            setLastError(error.localizedDescription)
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }
    }
}

@MainActor
private extension QuillCodeWorkspaceModel {
    func executeSubagentApproval(
        _ context: WorkspaceSubagentDecisionContext,
        workspaceRoot: URL
    ) async throws -> Bool {
        var record = context.record
        let target = context.target
        let workerIndex = context.workerIndex
        let pending = context.pending
        let plan = context.plan
        var child = context.child
        guard let childStore = subagentThreadStore,
              let payloadStore = subagentApprovalPayloadStore
        else { throw WorkspaceSubagentApprovalError.persistenceUnavailable }

        let parent = try parentThread(id: target.parentThreadID)
        let runProject = parent.projectID.flatMap(project(id:))
        let factory = agentSendSessionFactory(workspaceRoot: workspaceRoot, runProject: runProject)
        let prompt = child.messages.first(where: { $0.role == .user })?.content
            ?? WorkspaceSubagentPromptBuilder.prompt(
                objective: record.objective,
                job: WorkspaceSubagentJob(
                    runID: record.id,
                    id: record.workers[workerIndex].id,
                    childThreadID: record.workers[workerIndex].childThreadID,
                    name: record.workers[workerIndex].name,
                    role: record.workers[workerIndex].role,
                    objective: record.objective,
                    dependencyIDs: record.workers[workerIndex].dependencyIDs,
                    groupPath: record.workers[workerIndex].groupPath,
                    attempt: record.workers[workerIndex].attempt,
                    depth: record.workers[workerIndex].depth
                )
            )

        if plan.shouldRunTool {
            let heldCall = try payloadStore.load(pending.payloadKey)
            guard WorkspaceSubagentApprovalPayloadResolver.matches(
                heldCall,
                plan.request.toolCall
            ) else {
                throw WorkspaceSubagentApprovalError.payloadMismatch
            }
            record.workers[workerIndex].pendingApproval?.phase = .executing
            record.workers[workerIndex].updatedAt = Date()
            record.updatedAt = Date()
            try replaceSubagentRun(record, parentThreadID: target.parentThreadID)

            let runner = factory.configuredRunner(
                modelID: child.model,
                threadID: child.id,
                allowsSubagents: false
            )
            let execution = try await AgentRunRetryScope.$threadID.withValue(child.id) {
                try await runner.executeApprovedToolCall(
                    heldCall,
                    in: child,
                    workspaceRoot: workspaceRoot,
                    onProgress: { progressThread in
                        try? childStore.save(progressThread)
                    }
                )
            }
            child = execution.thread
            try childStore.save(child)
        }
        // Once the decision has either released its call or represented a non-tool spend gate,
        // the held payload is obsolete and must not survive as replayable state.
        try payloadStore.delete(pending.payloadKey)

        let session = factory.makeSession(
            prompt: prompt,
            thread: child,
            recordsUserMessage: false,
            allowsSubagents: false
        )
        let continuation = try await AgentRunRetryScope.$threadID.withValue(child.id) {
            try await session.run { progressThread in
                try? childStore.save(progressThread)
            }
        }
        child = continuation.thread
        try childStore.save(child)
        try checkpointSubagentContinuation(
            continuation,
            child: child,
            context: context,
            record: &record
        )

        let spawnIDs: Set<String> = record.workers[workerIndex].status == .completed
            ? [target.workerID]
            : []
        return await resumeSubagentRun(
            record,
            parentThreadID: target.parentThreadID,
            workspaceRoot: workspaceRoot,
            spawnFromWorkerIDs: spawnIDs
        )
    }

    func checkpointSubagentContinuation(
        _ continuation: WorkspaceAgentSendSessionResult,
        child: ChatThread,
        context: WorkspaceSubagentDecisionContext,
        record: inout SubagentRunRecord
    ) throws {
        let workerIndex = context.workerIndex
        if let nextApproval = WorkspaceApprovalActionPlanner.undecidedRequests(in: child).last {
            guard let payloadStore = subagentApprovalPayloadStore else {
                throw WorkspaceSubagentApprovalError.persistenceUnavailable
            }
            let nextPayloadKey = UUID()
            let nextPayload = try WorkspaceSubagentApprovalPayloadResolver.payload(
                for: nextApproval,
                heldToolCall: continuation.pendingApprovalToolCall
            )
            try payloadStore.save(nextPayload, key: nextPayloadKey)
            record.workers[workerIndex].status = .awaitingApproval
            record.workers[workerIndex].summary = WorkspaceContextSummarySanitizer.diagnostic(
                from: nextApproval.reason
            )
            record.workers[workerIndex].pendingApproval = SubagentPendingApproval(
                requestID: nextApproval.id,
                generation: context.pending.generation + 1,
                payloadKey: nextPayloadKey
            )
        } else {
            let answer = child.messages.last(where: { $0.role == .assistant })?.content ?? ""
            record.workers[workerIndex].status = .completed
            record.workers[workerIndex].summary = WorkspaceContextSummarySanitizer.summary(from: answer)
                .map(WorkspaceContextSummaryTextBounds.collapsedSingleLine)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "Completed \(record.workers[workerIndex].role)"
            record.workers[workerIndex].pendingApproval = nil
        }
        record.workers[workerIndex].updatedAt = Date()
        record.updatedAt = Date()
        try replaceSubagentRun(record, parentThreadID: context.target.parentThreadID)
    }

    func prepareSubagentDecision(
        _ action: ToolCardActionSurface
    ) throws -> WorkspaceSubagentDecisionContext {
        guard let target = action.subagentTarget,
              action.kind == .approve || action.kind == .deny,
              let childStore = subagentThreadStore,
              subagentApprovalPayloadStore != nil
        else {
            throw WorkspaceSubagentApprovalError.persistenceUnavailable
        }

        var record = try subagentRun(parentThreadID: target.parentThreadID, runID: target.runID)
        guard let workerIndex = record.workers.firstIndex(where: { $0.id == target.workerID }),
              let pending = record.workers[workerIndex].pendingApproval,
              pending.requestID == action.requestID,
              pending.generation == target.generation,
              pending.phase == .pending,
              record.workers[workerIndex].status == .awaitingApproval
        else {
            throw WorkspaceSubagentApprovalError.staleApproval
        }

        var child = try childStore.load(record.workers[workerIndex].childThreadID)
        guard let plan = WorkspaceApprovalActionPlanner.plan(action: action, thread: child),
              plan.request.id == pending.requestID
        else {
            throw WorkspaceSubagentApprovalError.staleApproval
        }
        if let decision = plan.decisionEvent {
            child.events.append(decision)
        }
        if !action.kind.approvesHeldTool, let notice = plan.assistantNotice {
            WorkspaceThreadNoticeAppender.appendAssistantNotice(notice, to: &child)
        }
        child.updatedAt = Date()
        try childStore.save(child)

        record.workers[workerIndex].pendingApproval?.phase = .decisionRecorded
        record.workers[workerIndex].updatedAt = Date()
        record.updatedAt = Date()
        try replaceSubagentRun(record, parentThreadID: target.parentThreadID)
        return WorkspaceSubagentDecisionContext(
            target: target,
            record: record,
            workerIndex: workerIndex,
            pending: pending,
            child: child,
            plan: plan
        )
    }

    func finishSubagentDenial(_ context: WorkspaceSubagentDecisionContext) throws {
        guard let payloadStore = subagentApprovalPayloadStore else {
            throw WorkspaceSubagentApprovalError.persistenceUnavailable
        }
        try payloadStore.delete(context.pending.payloadKey)
        var record = context.record
        record.workers[context.workerIndex].status = .cancelled
        record.workers[context.workerIndex].summary = "Skipped by the user"
        record.workers[context.workerIndex].pendingApproval = nil
        record.workers[context.workerIndex].updatedAt = Date()
        record.updatedAt = Date()
        try replaceSubagentRun(record, parentThreadID: context.target.parentThreadID)
    }

    func interruptSubagentApproval(_ target: WorkspaceSubagentApprovalTarget?) {
        guard let target,
              var record = try? subagentRun(parentThreadID: target.parentThreadID, runID: target.runID),
              let workerIndex = record.workers.firstIndex(where: { $0.id == target.workerID }),
              let phase = record.workers[workerIndex].pendingApproval?.phase,
              phase != .pending
        else { return }
        if let payload = record.workers[workerIndex].pendingApproval?.payloadKey {
            try? subagentApprovalPayloadStore?.delete(payload)
        }
        record.workers[workerIndex].status = .interrupted
        record.workers[workerIndex].summary = "Interrupted before completion"
        record.workers[workerIndex].pendingApproval = nil
        record.workers[workerIndex].updatedAt = Date()
        record.updatedAt = Date()
        try? replaceSubagentRun(record, parentThreadID: target.parentThreadID)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
    }
}

private struct WorkspaceSubagentDecisionContext {
    var target: WorkspaceSubagentApprovalTarget
    var record: SubagentRunRecord
    var workerIndex: Int
    var pending: SubagentPendingApproval
    var child: ChatThread
    var plan: WorkspaceApprovalActionPlan
}

enum WorkspaceSubagentApprovalError: LocalizedError {
    case missingParent
    case persistenceUnavailable
    case staleApproval
    case payloadMismatch

    var errorDescription: String? {
        switch self {
        case .missingParent:
            return "The delegated run's parent task is no longer available."
        case .persistenceUnavailable:
            return "The delegated approval store is unavailable."
        case .staleApproval:
            return "This delegated approval was already decided or replaced."
        case .payloadMismatch:
            return "The protected delegated action no longer matches its approval request."
        }
    }
}
