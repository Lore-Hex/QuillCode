import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopTerminalCoordinator {
    func runCommand(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        let command = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !tasks.isRunning(.terminal) else { return }

        draft = ""
        refresh()
        tasks.startIfIdle(.terminal) { [weak model] in
            guard let model else { return }
            await model.runTerminalCommand(
                command,
                workspaceRoot: model.activeWorkspaceRoot ?? fallbackWorkspaceRoot
            )
        } onFinish: {
            refresh()
        }
    }

    func recallPreviousCommand(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        recallCommand(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: refresh,
            recall: { $0.recallPreviousTerminalCommand() }
        )
    }

    func recallNextCommand(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        recallCommand(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: refresh,
            recall: { $0.recallNextTerminalCommand() }
        )
    }

    private func recallCommand(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void,
        recall: (QuillCodeWorkspaceModel) -> Bool
    ) {
        guard !tasks.isRunning(.terminal) else { return }
        if draft != model.terminal.draft {
            model.setTerminalDraft(draft)
        }
        guard recall(model) else { return }
        draft = model.terminal.draft
        refresh()
    }
}
