import QuillCodeCore
import QuillCodeTools

@MainActor
enum WorkspaceToolCallExecutorFactory {
    static func executor(
        model: QuillCodeWorkspaceModel,
        router: ToolRouter
    ) -> WorkspaceToolCallExecutor {
        WorkspaceToolCallExecutor(
            selectedProject: model.selectedProject,
            browser: model.browser,
            router: router,
            sshRemoteShellExecutor: model.sshRemoteShellExecutor
        )
    }
}
