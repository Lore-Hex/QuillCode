import Foundation
import QuillCodeApp
import QuillCodeTools

@MainActor
struct QuillCodeDesktopTerminalCoordinator {
    func runCommand(
        draft: inout String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        if tasks.isRunning(.terminal) {
            let input = draft
            guard !input.isEmpty, model.sendTerminalInput(input) else { return }
            draft = ""
            refresh()
            return
        }

        let command = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

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

    func resizeTerminal(_ windowSize: TerminalWindowSize, model: QuillCodeWorkspaceModel) {
        model.setTerminalWindowSize(
            rows: Int(windowSize.rows),
            columns: Int(windowSize.columns)
        )
    }

    func sendMouseInput(_ request: TerminalMouseInputRequest, model: QuillCodeWorkspaceModel) {
        model.sendTerminalMouseInput(request)
    }

    func suspendTerminal(model: QuillCodeWorkspaceModel) {
        model.suspendTerminalCommand()
    }

    func resumeTerminal(model: QuillCodeWorkspaceModel) {
        model.resumeTerminalCommand()
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
