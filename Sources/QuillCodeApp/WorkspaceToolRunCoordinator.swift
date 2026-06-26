import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
struct WorkspaceToolRunCoordinator {
    let model: QuillCodeWorkspaceModel
    let workspaceRoot: URL

    @discardableResult
    func run(_ call: ToolCall) -> ToolResult {
        if model.selectedThread == nil {
            _ = model.newChat()
        }
        guard model.selectedThread != nil else {
            return ToolResult(ok: false, error: "No active thread")
        }

        let contextProjectID = WorkspaceToolRunPreparer.effectiveProjectID(
            thread: model.selectedThread,
            fallbackProjectID: model.root.selectedProjectID
        )
        model.refreshProjectMetadata(contextProjectID)
        syncSelectedThreadContextForToolRun()

        let startPlan = WorkspaceToolRunLifecyclePlanner.started()
        model.setLastError(startPlan.lastError)
        model.refreshTopBar(agentStatus: startPlan.agentStatus)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let executor = WorkspaceToolCallExecutorFactory.executor(model: model, router: router)
        let execution = model.mutateBrowserState { browser, lastError in
            executor.execute(call, browser: &browser, lastError: &lastError)
        }
        let finishPlan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)
        recordToolRun(execution)

        if let thread = model.selectedThread {
            model.threadPersistence.save(thread)
        }
        model.refreshTopBar(agentStatus: finishPlan.agentStatus)
        return finishPlan.result
    }

    private func syncSelectedThreadContextForToolRun() {
        let fallbackProjectID = model.root.selectedProjectID
        let projects = model.root.projects
        let globalMemories = model.root.globalMemories
        model.mutateSelectedThread { thread in
            _ = WorkspaceToolRunPreparer.syncThreadContext(
                &thread,
                fallbackProjectID: fallbackProjectID,
                projects: projects,
                globalMemories: globalMemories
            )
        }
    }

    private func recordToolRun(_ execution: WorkspaceToolCallExecution) {
        model.mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(execution: execution, to: &thread)
        }
    }
}
