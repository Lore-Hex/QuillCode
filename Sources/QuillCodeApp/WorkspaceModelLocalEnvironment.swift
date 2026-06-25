import Foundation
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = LocalEnvironmentActionMatcher.action(
            withID: actionID,
            in: selectedProject?.localActions ?? []
        ) else {
            return false
        }

        runToolCall(
            WorkspaceShellToolCallPlanner.localEnvironmentAction(action),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        let plan = WorkspaceEnvironmentSlashCommandPlanner.plan(
            query: query,
            userText: originalPrompt,
            actions: selectedProject?.localActions ?? []
        )
        switch plan {
        case .transcript(let transcript):
            appendLocalCommandTranscript(transcript)
        case .runAction(let actionID):
            _ = runLocalEnvironmentAction(actionID, workspaceRoot: workspaceRoot)
        }
    }
}
