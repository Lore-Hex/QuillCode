import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
public extension QuillCodeWorkspaceModel {
    @discardableResult
    func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        if selectedThread == nil {
            _ = newChat()
        }
        guard selectedThread != nil else {
            return ToolResult(ok: false, error: "No active thread")
        }

        let contextProjectID = WorkspaceToolRunPreparer.effectiveProjectID(
            thread: selectedThread,
            fallbackProjectID: root.selectedProjectID
        )
        refreshProjectMetadata(contextProjectID)
        syncSelectedThreadContextForToolRun()

        let startPlan = WorkspaceToolRunLifecyclePlanner.started()
        setLastError(startPlan.lastError)
        refreshTopBar(agentStatus: startPlan.agentStatus)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let executor = workspaceToolCallExecutor(router: router)
        let execution = mutateBrowserState { browser, lastError in
            executor.execute(call, browser: &browser, lastError: &lastError)
        }
        let finishPlan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)
        recordToolRun(execution)

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: finishPlan.agentStatus)
        return finishPlan.result
    }
}

@MainActor
extension QuillCodeWorkspaceModel {
    func workspaceToolCallExecutor(router: ToolRouter) -> WorkspaceToolCallExecutor {
        WorkspaceToolCallExecutor(
            selectedProject: selectedProject,
            browser: browser,
            router: router,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }
}

@MainActor
private extension QuillCodeWorkspaceModel {
    func syncSelectedThreadContextForToolRun() {
        let fallbackProjectID = root.selectedProjectID
        let projects = root.projects
        let globalMemories = root.globalMemories
        mutateSelectedThread { thread in
            _ = WorkspaceToolRunPreparer.syncThreadContext(
                &thread,
                fallbackProjectID: fallbackProjectID,
                projects: projects,
                globalMemories: globalMemories
            )
        }
    }

    func recordToolRun(_ execution: WorkspaceToolCallExecution) {
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(execution: execution, to: &thread)
        }
    }
}
