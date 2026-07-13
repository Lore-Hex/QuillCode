import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func runCommand(_ command: WorkspaceCommandSurface) {
        guard let action = QuillCodeDesktopCommandPlanner.action(for: command) else { return }
        commandCoordinator.run(action, performer: self)
    }

    func openCommandPalette() {
        isCommandPalettePresented = true
    }

    func openKeyboardShortcuts() {
        isKeyboardShortcutsPresented = true
    }

    func openSettings() {
        isSettingsPresented = true
    }

    func stopAll() {
        activeWorkCoordinator.stopAll(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func disconnectAll() {
        activeWorkCoordinator.disconnectAll(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }
}

extension QuillCodeDesktopController: QuillCodeDesktopCommandPerforming {
    func refreshComputerUseStatus() {
        refresh()
    }

    func runWorkspaceCommand(_ commandID: String) {
        // Push the live draft so thread-changing commands (new chat / duplicate /
        // fork / compact) stash it instead of reading a stale model draft.
        model.setDraft(draft)
        if commandID == "side-conversation-return" || commandID == "new-chat" {
            cancelSelectedSideConversationTask()
        }
        guard workspaceActionCoordinator.runWorkspaceCommand(
            commandID,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        ) else {
            return
        }
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        if commandID == "browser-back" {
            browserCoordinator.goBackOpenSession(model: model)
        } else if commandID == "browser-forward" {
            browserCoordinator.goForwardOpenSession(model: model)
        } else if commandID == "browser-reload" {
            browserCoordinator.syncOpenSession(model: model)
            browserCoordinator.reloadOpenSession()
        } else {
            browserCoordinator.syncOpenSession(model: model)
        }
        refresh()
    }
}
