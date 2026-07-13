import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func recordSubagentRun(_ record: SubagentRunRecord, threadID: UUID) {
        mutateThread(threadID) { thread in
            if let index = thread.subagentRuns.firstIndex(where: { $0.id == record.id }) {
                var next = record
                next.lastPublishedSummary = thread.subagentRuns[index].lastPublishedSummary
                thread.subagentRuns[index] = next
            } else {
                thread.subagentRuns.append(record)
            }
            thread.updatedAt = Date()
        }
    }

    func publishSubagentRunSummary(_ summary: String, runID: UUID, threadID: UUID) {
        mutateThread(threadID) { thread in
            guard let index = thread.subagentRuns.firstIndex(where: { $0.id == runID }),
                  thread.subagentRuns[index].lastPublishedSummary != summary
            else { return }
            thread.messages.append(ChatMessage(role: .assistant, content: summary))
            thread.events.append(ThreadEvent(kind: .message, summary: summary))
            thread.subagentRuns[index].lastPublishedSummary = summary
            thread.subagentRuns[index].updatedAt = Date()
        }
    }

    /// Removes every hidden child transcript and still-held raw approval associated with a parent.
    /// Returns managed image attachments so the normal image GC can reclaim them with the parent.
    func removeSubagentArtifacts(for thread: ChatThread) -> [ChatAttachment] {
        var attachments: [ChatAttachment] = []
        var deletedChildren = Set<UUID>()
        var deletedPayloads = Set<UUID>()
        for worker in thread.subagentRuns.flatMap(\.workers) {
            if deletedChildren.insert(worker.childThreadID).inserted {
                if let store = subagentThreadStore,
                   let child = try? store.load(worker.childThreadID) {
                    attachments += child.composerAttachments
                    attachments += child.followUpQueue.flatMap(\.attachments)
                    attachments += child.messages.flatMap(\.attachments)
                }
                if let store = subagentThreadStore {
                    try? store.delete(worker.childThreadID)
                }
            }
            if let key = worker.pendingApproval?.payloadKey,
               deletedPayloads.insert(key).inserted,
               let store = subagentApprovalPayloadStore {
                try? store.delete(key)
            }
        }
        return attachments
    }

    func resumeSubagentRun(
        _ record: SubagentRunRecord,
        parentThreadID: UUID,
        workspaceRoot: URL,
        spawnFromWorkerIDs: Set<String>
    ) async -> Bool {
        guard let parent = root.threads.first(where: { $0.id == parentThreadID }) else { return false }
        let runProject = parent.projectID.flatMap(project(id:))
        let scheduler = subagentSchedulerOverride ?? WorkspaceSubagentScheduler(
            maxDepth: record.maxDepth,
            maxTotalJobs: record.maxTotalJobs,
            detailedWorker: AgentWorkspaceSubagentWorker.scheduledWorker(
                sessionFactory: agentSendSessionFactory(
                    workspaceRoot: workspaceRoot,
                    runProject: runProject
                ),
                parentThread: parent,
                threadStore: subagentThreadStore,
                approvalPayloadStore: subagentApprovalPayloadStore
            )
        )
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)
        let result = await scheduler.resume(
            record: record,
            spawnFromWorkerIDs: spawnFromWorkerIDs,
            state: { [weak self] next in
                await self?.recordSubagentRun(next, threadID: parentThreadID)
            },
            spawn: { _, summary in
                WorkspaceSubagentSpawnDirectiveParser.parse(summary)
            }
        )
        publishSubagentRunSummary(result.summary, runID: record.id, threadID: parentThreadID)
        let status = result.record.workers.contains(where: { $0.status == .awaitingApproval })
            ? TopBarAgentStatusLabel.review
            : TopBarAgentStatusLabel.idle
        refreshTopBar(agentStatus: status)
        setLastError(nil)
        return true
    }

    func subagentRun(parentThreadID: UUID, runID: UUID) throws -> SubagentRunRecord {
        let parent = try parentThread(id: parentThreadID)
        guard let record = parent.subagentRuns.first(where: { $0.id == runID }) else {
            throw WorkspaceSubagentApprovalError.staleApproval
        }
        return record
    }

    func parentThread(id: UUID) throws -> ChatThread {
        guard let parent = root.threads.first(where: { $0.id == id }) else {
            throw WorkspaceSubagentApprovalError.missingParent
        }
        return parent
    }

    func replaceSubagentRun(_ record: SubagentRunRecord, parentThreadID: UUID) throws {
        guard let parentIndex = root.threads.firstIndex(where: { $0.id == parentThreadID }),
              let runIndex = root.threads[parentIndex].subagentRuns.firstIndex(where: { $0.id == record.id })
        else {
            throw WorkspaceSubagentApprovalError.staleApproval
        }
        var parent = root.threads[parentIndex]
        var next = record
        next.lastPublishedSummary = parent.subagentRuns[runIndex].lastPublishedSummary
        parent.subagentRuns[runIndex] = next
        parent.updatedAt = Date()
        try threadPersistence.saveOrThrow(parent)
        root.threads[parentIndex] = parent
    }
}
