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
            browserDomainPolicy: model.root.config.browserDomainPolicy,
            router: router,
            sshRemoteShellExecutor: model.sshRemoteShellExecutor
        )
    }
}
