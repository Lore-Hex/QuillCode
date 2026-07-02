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

        // App/UI-initiated tool runs use the model's UI edit session — never a chat thread's —
        // so a UI read grants no model thread write rights (and vice versa).
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: model.uiEditSessionGuard)
        let executor = WorkspaceToolCallExecutorFactory.executor(model: model, router: router)
        let execution = model.mutateBrowserState { browser, lastError in
            executor.execute(call, browser: &browser, lastError: &lastError)
        }
        let finishPlan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)
        recordToolRun(execution)

        if let thread = model.selectedThread {
            model.threadPersistence.save(thread)
        }
        // Capture branch + ahead/behind AND the changed-file set from a successful git
        // status (one stdout, no extra git invocation): the chip reflects the branch, and
        // `@` mentions boost/badge the files you just changed.
        if call.name == ToolDefinition.gitStatus.name, finishPlan.result.ok {
            model.setBranchStatus(
                GitBranchStatus.parse(statusShortBranchOutput: finishPlan.result.stdout),
                forProjectID: model.selectedThread?.projectID ?? model.root.selectedProjectID
            )
            // The changed set feeds the `@` mention index, which is built from
            // `root.selectedProjectID`, so it is tagged with that same project notion.
            model.setChangedFilePaths(
                GitChangedFiles.parse(statusShortBranchOutput: finishPlan.result.stdout),
                forProjectID: model.root.selectedProjectID
            )
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
