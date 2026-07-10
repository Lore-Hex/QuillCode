import QuillCodeApp
import QuillCodeTools

@MainActor
extension QuillCodeDesktopController {
    func runTerminalCommand() {
        terminalCoordinator.runCommand(
            draft: &terminalDraft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func recallPreviousTerminalCommand() {
        terminalCoordinator.recallPreviousCommand(
            draft: &terminalDraft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func recallNextTerminalCommand() {
        terminalCoordinator.recallNextCommand(
            draft: &terminalDraft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func resizeTerminal(_ windowSize: TerminalWindowSize) {
        terminalCoordinator.resizeTerminal(windowSize, model: model)
    }

    func sendTerminalMouseInput(_ request: TerminalMouseInputRequest) {
        terminalCoordinator.sendMouseInput(request, model: model)
    }

    func suspendTerminal() {
        terminalCoordinator.suspendTerminal(model: model)
        // Rebuild the published surface so the pane re-renders with the new isSuspended state
        // (Resume replaces Suspend). isSuspended is a visible surface field, unlike resize.
        refresh()
    }

    func resumeTerminal() {
        terminalCoordinator.resumeTerminal(model: model)
        refresh()
    }
}
