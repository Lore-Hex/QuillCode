import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
public extension QuillCodeWorkspaceModel {
    @discardableResult
    func runLatestTurnRevert(workspaceRoot: URL) -> Bool {
        guard let thread = selectedThread,
              let plan = WorkspaceTurnRevertPlanner.latestPlan(in: thread)
        else {
            setLastError("This turn can no longer be reverted.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }
        return runTurnRevert(turnMessageID: plan.turnMessageID, workspaceRoot: workspaceRoot)
    }

    /// Reverts a turn's `apply_patch` edits via the honest reverse-patch engine, records the
    /// result as a transcript tool run, and — on success — refreshes the diff so the review
    /// pane reflects the reverted tree. Returns whether the revert applied. Never restores
    /// to HEAD; a turn whose lines changed since fails with the engine's own message.
    @discardableResult
    func runTurnRevert(turnMessageID: UUID, workspaceRoot: URL) -> Bool {
        // Reverting reverse-applies the patch with LOCAL git, so it cannot operate on a
        // remote project's tree — refuse rather than touch the wrong (local) directory.
        guard selectedProject?.isRemote != true else {
            setLastError("Reverting a turn is only supported for local projects.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }

        guard let thread = selectedThread,
              let plan = WorkspaceTurnRevertPlanner.plan(for: turnMessageID, in: thread)
        else {
            setLastError("This turn can no longer be reverted.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }

        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: workspaceRoot, patches: plan.patches)
        // Record the revert as a transcript tool run so it is visible and itself revertible.
        let revertCall = ToolCall(name: WorkspaceTurnRevertPlanner.revertTurnToolName, argumentsJSON: "{}")
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(call: revertCall, result: result, to: &thread)
        }

        if result.ok {
            _ = runToolCall(
                ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
        } else {
            setLastError(result.error ?? "Could not cleanly revert this turn — files changed since it ran.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
        }

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        return result.ok
    }
}
