import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func runSubagentSlashCommand(
        _ request: WorkspaceSubagentRunRequest,
        originalPrompt: String,
        workspaceRoot: URL
    ) async {
        if selectedThread == nil {
            _ = newChat()
        }
        guard let threadID = root.selectedThreadID else { return }
        mutateThread(threadID) { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = "Subagents"
            }
            thread.messages.append(ChatMessage(role: .user, content: originalPrompt))
            thread.events.append(ThreadEvent(kind: .message, summary: originalPrompt))
        }
        guard let parentThread = root.threads.first(where: { $0.id == threadID }) else { return }

        let runProject = parentThread.projectID.flatMap(project(id:))
        let runID = UUID()
        let sessionFactory = agentSendSessionFactory(
            workspaceRoot: workspaceRoot,
            runProject: runProject
        )
        let usesLegacyStorage = subagentSchedulerOverride == nil
            && (subagentThreadStore == nil || subagentApprovalPayloadStore == nil)
        let scheduler: WorkspaceSubagentScheduler
        if let subagentSchedulerOverride {
            scheduler = subagentSchedulerOverride
        } else if usesLegacyStorage {
            scheduler = WorkspaceSubagentScheduler(
                legacyWorker: AgentWorkspaceSubagentWorker.legacyScheduledWorker(
                    sessionFactory: sessionFactory,
                    parentThread: parentThread
                )
            )
        } else {
            scheduler = WorkspaceSubagentScheduler(
                detailedWorker: AgentWorkspaceSubagentWorker.scheduledWorker(
                    sessionFactory: sessionFactory,
                    parentThread: parentThread,
                    threadStore: subagentThreadStore,
                    approvalPayloadStore: subagentApprovalPayloadStore
                )
            )
        }

        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)
        // A worker may delegate sub-tasks by emitting `[[DELEGATE: name | role]]` markers; the parser
        // turns them into bounded child workers and the scheduler enforces depth/total-job limits.
        let result = await scheduler.run(
            request: request,
            runID: runID,
            state: { [weak self] record in
                await self?.recordSubagentRun(record, threadID: threadID)
            },
            spawn: { _, summary in
                WorkspaceSubagentSpawnDirectiveParser.parse(summary)
            }
        )
        guard !Task.isCancelled else {
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
            return
        }

        if usesLegacyStorage {
            finishSubagentSchedulerResult(result, parentThreadID: threadID)
            return
        }

        publishSubagentRunSummary(result.summary, runID: runID, threadID: threadID)
        let status = result.record.workers.contains(where: { $0.status == .awaitingApproval })
            ? TopBarAgentStatusLabel.review
            : TopBarAgentStatusLabel.idle
        refreshTopBar(agentStatus: status)
    }

    /// Compatibility projection for whole-session subagent records created by the previous build.
    func recordSubagentProgress(_ update: SubagentProgressUpdate, threadID: UUID) {
        let argumentsJSON = (try? JSONHelpers.encodePretty(update))
            ?? #"{"subagents":[]}"#
        let call = ToolCall(name: ToolDefinition.subagentsUpdate.name, argumentsJSON: argumentsJSON)
        let result = SubagentProgressToolExecutor.execute(call)
        mutateThread(threadID) { thread in
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        }
    }

    func finishSubagentSchedulerResult(
        _ result: WorkspaceSubagentRunResult,
        parentThreadID: UUID
    ) {
        if result.isPaused {
            guard let subagentSessionStore else {
                failSubagentRun(
                    parentThreadID: parentThreadID,
                    message: "Delegated work paused, but its private continuation store is unavailable."
                )
                return
            }
            do {
                let existing = try? subagentSessionStore.load(result.state.id)
                try subagentSessionStore.save(WorkspaceSubagentSessionRecord(
                    parentThreadID: parentThreadID,
                    state: result.state,
                    createdAt: existing?.createdAt ?? Date(),
                    updatedAt: Date()
                ))
                recordSubagentProgress(result.update, threadID: parentThreadID)
                refreshTopBar(agentStatus: TopBarAgentStatusLabel.review)
            } catch {
                failSubagentRun(
                    parentThreadID: parentThreadID,
                    message: "Could not save delegated approval state: \(error.localizedDescription)"
                )
            }
            return
        }

        try? subagentSessionStore?.delete(result.state.id)
        recordSubagentProgress(result.update, threadID: parentThreadID)
        mutateThread(parentThreadID) { thread in
            thread.messages.append(ChatMessage(role: .assistant, content: result.summary))
            thread.events.append(ThreadEvent(kind: .message, summary: result.summary))
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    private func failSubagentRun(parentThreadID: UUID, message: String) {
        mutateThread(parentThreadID) { thread in
            thread.messages.append(ChatMessage(role: .assistant, content: message))
            thread.events.append(ThreadEvent(kind: .message, summary: message))
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
    }
}
