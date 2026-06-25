import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func createWorktree(_ request: WorkspaceWorktreeCreateRequest, workspaceRoot: URL) {
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.create(request),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openToolResultWorktree(result) { projectID in
                worktreeOpenContext(projectID: projectID, request: request)
            }
        }
    }

    public func openWorktree(_ request: WorkspaceWorktreeOpenRequest, workspaceRoot: URL) {
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.open(request),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openToolResultWorktree(result) { projectID in
                worktreeOpenContext(projectID: projectID, request: request)
            }
        }
    }

    public func worktreeChoiceLoadRequest(workspaceRoot: URL) -> WorkspaceWorktreeChoiceLoadRequest {
        WorkspaceWorktreeChoiceLoadRequest(
            workspaceRoot: workspaceRoot,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    public func worktreeChoiceLoad(workspaceRoot: URL) -> WorkspaceWorktreeChoiceLoad {
        worktreeChoiceLoadRequest(workspaceRoot: workspaceRoot).load()
    }

    public func worktreeChoices(workspaceRoot: URL) -> [WorkspaceWorktreeChoice] {
        worktreeChoiceLoad(workspaceRoot: workspaceRoot).choices
    }

    public func worktreePrunePreviewLoadRequest(workspaceRoot: URL) -> WorkspaceWorktreePrunePreviewLoadRequest {
        WorkspaceWorktreePrunePreviewLoadRequest(
            workspaceRoot: workspaceRoot,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    public func worktreePrunePreview(workspaceRoot: URL) -> WorkspaceWorktreePrunePreview {
        worktreePrunePreviewLoadRequest(workspaceRoot: workspaceRoot).load()
    }

    public func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest, workspaceRoot: URL) {
        runToolCall(
            WorkspaceWorktreeToolCallPlanner.remove(request),
            workspaceRoot: workspaceRoot
        )
    }

    public func pruneWorktrees(_ request: WorkspaceWorktreePruneRequest, workspaceRoot: URL) {
        runToolCall(
            WorkspaceWorktreeToolCallPlanner.prune(request),
            workspaceRoot: workspaceRoot
        )
    }

    private func openToolResultWorktree(
        _ result: ToolResult,
        context: (UUID) -> WorkspaceWorktreeOpenContext
    ) {
        guard let artifact = result.artifacts.first else { return }
        if selectedProject?.isRemote == true {
            openToolResultRemoteWorktree(artifact, context: context)
            return
        }
        let worktreeURL = URL(fileURLWithPath: artifact).standardizedFileURL
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return }

        let projectID = addProject(
            path: worktreeURL,
            name: WorkspaceProjectEngine.defaultProjectName(for: worktreeURL)
        )
        refreshProjectMetadata(projectID)

        let opened = WorkspaceWorktreeOpenEngine.localThread(
            worktreeURL: worktreeURL,
            context: context(projectID)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func openToolResultRemoteWorktree(
        _ artifact: String,
        context: (UUID) -> WorkspaceWorktreeOpenContext
    ) {
        guard let connection = ProjectConnection.parseSSH(artifact),
              let projectID = addSSHProject(
                artifact,
                name: WorkspaceProjectEngine.defaultSSHProjectName(for: connection)
              ) else {
            return
        }

        let opened = WorkspaceWorktreeOpenEngine.remoteThread(
            connection: connection,
            context: context(projectID)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeCreateRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceProjectContextRefresher.worktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeOpenRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceProjectContextRefresher.worktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func openCreatedWorktreeThread(_ thread: ChatThread, projectID: UUID) {
        _ = insertCreatedThread(thread, selectedProjectID: projectID, saveThread: true)
    }
}
