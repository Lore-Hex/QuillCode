import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceCancellableToolRunContext: Sendable, Hashable {
    let threadID: UUID
    let projectID: UUID?
    let call: ToolCall
    let workspaceRoot: URL
}

@MainActor
struct WorkspaceCancellableToolRunCoordinator {
    let model: QuillCodeWorkspaceModel

    func run(
        _ call: ToolCall,
        workspaceRoot: URL,
        threadID: UUID? = nil,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> ToolResult? {
        guard !Task.isCancelled,
              let context = begin(call, workspaceRoot: workspaceRoot, threadID: threadID)
        else {
            return nil
        }

        onProgressUpdated?()
        await Task.yield()
        markRunning(context)
        onProgressUpdated?()

        let result: ToolResult
        if let runner = model.cancellableToolRunner {
            result = await runner(context.call, context.workspaceRoot)
        } else {
            let router = ToolRouter(
                workspaceRoot: context.workspaceRoot,
                managedWorktreeRoot: model.managedWorktreeRoot,
                editGuard: model.uiEditSessionGuard
            )
            result = await router.executeCancellable(context.call)
        }
        finish(context, result: result, wasCancelled: Task.isCancelled)
        onProgressUpdated?()
        return result
    }

    private func begin(
        _ call: ToolCall,
        workspaceRoot: URL,
        threadID requestedThreadID: UUID?
    ) -> WorkspaceCancellableToolRunContext? {
        if requestedThreadID == nil, model.selectedThread == nil {
            _ = model.newChat()
        }
        guard let threadID = requestedThreadID ?? model.root.selectedThreadID,
              model.root.threads.contains(where: { $0.id == threadID }),
              !model.agentRuns.isRunning(threadID),
              model.activeCancellableToolRunThreadIDs.insert(threadID).inserted
        else {
            model.setLastError("This chat already has active work.")
            return nil
        }

        let fallbackProjectID = model.root.selectedProjectID
        let projects = model.root.projects
        let globalMemories = model.root.globalMemories
        var projectID: UUID?
        let didMutate = model.mutateThread(threadID) { thread in
            projectID = WorkspaceToolRunPreparer.syncThreadContext(
                &thread,
                fallbackProjectID: fallbackProjectID,
                projects: projects,
                globalMemories: globalMemories
            ).projectID
            thread.events.append(WorkspaceToolEventRecorder.queuedEvent(for: call))
        } != nil
        guard didMutate else {
            model.activeCancellableToolRunThreadIDs.remove(threadID)
            return nil
        }

        model.setLastError(nil)
        if model.root.selectedThreadID == threadID {
            model.refreshTopBar(agentStatus: TopBarAgentStatusLabel.queued)
        }
        return WorkspaceCancellableToolRunContext(
            threadID: threadID,
            projectID: projectID,
            call: call,
            workspaceRoot: workspaceRoot.standardizedFileURL
        )
    }

    private func markRunning(_ context: WorkspaceCancellableToolRunContext) {
        guard model.activeCancellableToolRunThreadIDs.contains(context.threadID) else { return }
        model.mutateThread(context.threadID) { thread in
            thread.events.append(WorkspaceToolEventRecorder.runningEvent(for: context.call))
        }
        if model.root.selectedThreadID == context.threadID {
            model.refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)
        }
    }

    private func finish(
        _ context: WorkspaceCancellableToolRunContext,
        result: ToolResult,
        wasCancelled: Bool
    ) {
        model.activeCancellableToolRunThreadIDs.remove(context.threadID)
        model.mutateThread(context.threadID) { thread in
            thread.events.append(
                WorkspaceToolEventRecorder.completionEvent(for: context.call, result: result)
            )
        }
        if let projectID = context.projectID {
            model.requestProjectContextRefresh(projectID, queueAfterInFlight: true)
        }
        guard model.root.selectedThreadID == context.threadID else { return }
        let fallbackStatus = wasCancelled
            ? TopBarAgentStatusLabel.stopped
            : (result.ok ? TopBarAgentStatusLabel.idle : TopBarAgentStatusLabel.failed)
        model.refreshSelectedAgentRunPresentation(fallbackStatus: fallbackStatus)
    }

}
