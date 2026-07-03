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
        guard !prompt.isEmpty else { return }

        // Never lock the composer: a submit arriving DURING a live run enqueues as a follow-up
        // chip (drained at the next turn boundary by the run's own drain loop) instead of being
        // silently rejected. When idle, it sends immediately as before.
        if tasks.isRunning(.send) {
            model.enqueueFollowUp(prompt)
            draft = ""
            refresh()
            return
        }

        model.setDraft(prompt)
        draft = ""
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
            await model.submitComposer(
                workspaceRoot: model.activeWorkspaceRoot ?? fallbackWorkspaceRoot,
                onStarted: refresh,
                onProgressUpdated: refresh
            )
        } onFinish: {
            refresh()
        }
    }
}
