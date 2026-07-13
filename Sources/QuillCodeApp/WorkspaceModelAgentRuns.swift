import Foundation

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

    func beginAgentRun(threadID: UUID, lifecycle: WorkspaceComposerSendLifecyclePlan) {
        agentRuns.begin(threadID: threadID, status: lifecycle.agentStatus)
        guard root.selectedThreadID == threadID else {
            refreshSelectedAgentRunPresentation()
            return
        }
        applyComposerSendLifecycle(lifecycle)
    }

    func updateAgentRun(threadID: UUID, status: String) {
        agentRuns.update(threadID: threadID, status: status)
        guard root.selectedThreadID == threadID else { return }
        composer.isSending = true
        setLastError(nil)
        refreshTopBar(agentStatus: status)
    }

    func finishAgentRun(
        threadID: UUID,
        lifecycle: WorkspaceComposerSendLifecyclePlan
    ) {
        agentRuns.finish(threadID: threadID)
        enforceManagedWorktreeRetention()
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
        guard agentRuns.activeCount > 0 else { return nil }
        return agentRuns.activeCount == 1 ? "1 chat running" : "\(agentRuns.activeCount) chats running"
    }
}
