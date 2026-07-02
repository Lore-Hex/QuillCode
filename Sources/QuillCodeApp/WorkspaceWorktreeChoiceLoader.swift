import Foundation
import QuillCodeCore
import QuillCodeTools

public struct WorkspaceWorktreeChoiceLoadRequest: Sendable {
    public var workspaceRoot: URL
    public var selectedProject: ProjectRef?
    public var sshRemoteShellExecutor: SSHRemoteShellExecutor

    public init(
        workspaceRoot: URL,
        selectedProject: ProjectRef?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor()
    ) {
        self.workspaceRoot = workspaceRoot
        self.selectedProject = selectedProject
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
    }

    public func load() -> WorkspaceWorktreeChoiceLoad {
        let call = WorkspaceWorktreeToolCallPlanner.list()
        let result: ToolResult
        if let selectedProject, selectedProject.isRemote {
            result = WorkspaceRemoteProjectToolExecutor.execute(
                call,
                project: selectedProject,
                executor: sshRemoteShellExecutor
            )
        } else {
            // Detached edit session: this loader only runs read-only git worktree tools,
            // so nothing here may mark or consult any model session's read-set.
            result = ToolRouter(workspaceRoot: workspaceRoot, editGuard: FileEditSessionGuard()).execute(call)
        }
        guard result.ok else {
            return WorkspaceWorktreeChoiceLoad(errorMessage: Self.errorMessage(from: result))
        }
        return WorkspaceWorktreeChoiceLoad(
            choices: WorkspaceWorktreeListSurfaceBuilder.choices(
                fromPorcelain: result.stdout,
                selectedProjectPath: selectedProject?.connection.path ?? selectedProject?.path ?? workspaceRoot.path
            )
        )
    }

    private static func errorMessage(from result: ToolResult) -> String {
        let candidates = [result.error, result.stderr]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let message = candidates.first else {
            return "Could not load registered git worktrees."
        }
        return String(message.prefix(240))
    }
}
