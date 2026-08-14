import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public var activeAgentRunThreadIDs: Set<UUID> {
        agentRuns.activeThreadIDs
    }

    public var activeAgentRunCount: Int {
        agentRuns.activeCount
    }

    public func isAgentRunActive(for threadID: UUID?) -> Bool {
        agentRuns.isRunning(threadID)
    }

    public func lastAgentRunStopReason(for threadID: UUID?) -> AgentRunStopReason? {
        guard let threadID else { return nil }
        return completedAgentRunStopReasons[threadID]
    }

    @discardableResult
    func beginAgentRun(
        threadID: UUID,
        lifecycle: WorkspaceComposerSendLifecyclePlan,
        runID: UUID = UUID(),
        startedAt: Date = Date()
    ) -> UUID {
        completedAgentRunStopReasons.removeValue(forKey: threadID)
        interruptedRunRecoveryThreadIDs.remove(threadID)
        if lastError == WorkspaceAgentRunRelaunchReconciler.recoveryMessage {
            setLastError(nil)
        }
        mutateThread(threadID) { thread in
            thread.activeRunCheckpoint = ThreadRunCheckpoint(
                id: runID,
                startedAt: startedAt,
                messageCountAtStart: thread.messages.count,
                eventCountAtStart: thread.events.count
            )
        }
        agentRuns.begin(threadID: threadID, runID: runID, status: lifecycle.agentStatus)
        guard root.selectedThreadID == threadID else {
            refreshSelectedAgentRunPresentation()
            return runID
        }
        applyComposerSendLifecycle(lifecycle)
        return runID
    }

    func updateAgentRun(threadID: UUID, runID: UUID? = nil, status: String) {
        if let runID {
            guard agentRuns.isRunning(threadID, runID: runID) else { return }
        } else {
            guard agentRuns.isRunning(threadID) else { return }
        }
        agentRuns.update(threadID: threadID, runID: runID, status: status)
        guard root.selectedThreadID == threadID else { return }
        composer.isSending = true
        setLastError(nil)
        refreshTopBar(agentStatus: status)
    }

    func recordAgentRunStopReason(_ stopReason: AgentRunStopReason, threadID: UUID) {
        completedAgentRunStopReasons[threadID] = stopReason
    }

    func clearAgentRunStopReason(threadID: UUID) {
        completedAgentRunStopReasons.removeValue(forKey: threadID)
    }

    func finishAgentRun(
        threadID: UUID,
        runID: UUID? = nil,
        lifecycle: WorkspaceComposerSendLifecyclePlan
    ) {
        let resolvedRunID = runID ?? agentRuns.runID(for: threadID)
        guard let resolvedRunID,
              agentRuns.finish(threadID: threadID, runID: resolvedRunID) != nil
        else {
            return
        }
        mutateThread(threadID) { thread in
            guard thread.activeRunCheckpoint?.id == resolvedRunID else { return }
            thread.activeRunCheckpoint = nil
        }
        enforceManagedWorktreeRetention()
        enforceThreadPayloadResidency()
        guard root.selectedThreadID == threadID else {
            refreshSelectedAgentRunPresentation()
            return
        }
        var selectedLifecycle = lifecycle
        if lifecycle.agentStatus == TopBarAgentStatusLabel.idle,
           let backgroundStatus = backgroundAgentRunStatusLabel {
            selectedLifecycle.agentStatus = backgroundStatus
        }
        applyComposerSendLifecycle(selectedLifecycle)
    }

    func refreshSelectedAgentRunPresentation(fallbackStatus: String = TopBarAgentStatusLabel.idle) {
        let selectedThreadID = root.selectedThreadID
        composer.isSending = agentRuns.isRunning(selectedThreadID)
        let status = agentRuns.status(for: selectedThreadID)
            ?? backgroundAgentRunStatusLabel
            ?? fallbackStatus
        refreshTopBar(agentStatus: status)
    }

    var backgroundAgentRunStatusLabel: String? {
        let activeThreadIDs = agentRuns.activeThreadIDs.union(activeCancellableToolRunThreadIDs)
        guard !activeThreadIDs.isEmpty else { return nil }
        return activeThreadIDs.count == 1 ? "1 chat running" : "\(activeThreadIDs.count) chats running"
    }
}
