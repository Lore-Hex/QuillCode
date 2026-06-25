import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopComposerCoordinator {
    func send(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !tasks.isRunning(.send) else { return }

        model.setDraft(prompt)
        draft = ""
        refresh()
        submitPreparedComposer(
            model: model,
            fallbackWorkspaceRoot: fallbackWorkspaceRoot,
            tasks: tasks,
            refresh: refresh
        )
    }

    func retryLastTurn(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        guard !tasks.isRunning(.send), model.prepareRetryLastUserTurn() else { return }

        draft = ""
        refresh()
        submitPreparedComposer(
            model: model,
            fallbackWorkspaceRoot: fallbackWorkspaceRoot,
            tasks: tasks,
            refresh: refresh
        )
    }

    private func submitPreparedComposer(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        tasks.startIfIdle(.send) { [weak model] in
            guard let model else { return }
            await model.submitComposer(workspaceRoot: model.activeWorkspaceRoot ?? fallbackWorkspaceRoot)
        } onFinish: {
            refresh()
        }
    }
}
