import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func send() {
        composerCoordinator.send(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func retryLastTurn() {
        composerCoordinator.retryLastTurn(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func toggleTerminal() {
        paneCoordinator.toggleTerminal(on: model)
        refresh()
    }

    func toggleBrowser() {
        paneCoordinator.toggleBrowser(on: model)
        refresh()
    }

    func toggleExtensions() {
        paneCoordinator.toggleExtensions(on: model)
        refresh()
    }

    func toggleMemories() {
        paneCoordinator.toggleMemories(on: model)
        refresh()
    }

    func toggleActivity() {
        paneCoordinator.toggleActivity(on: model)
        refresh()
    }

    func toggleAutomations() {
        paneCoordinator.toggleAutomations(on: model)
        refresh()
    }

    func openBrowserPreview() {
        browserCoordinator.openPreview(
            model: model,
            addressDraft: browserAddressDraft,
            workspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func openBrowserSession() {
        browserCoordinator.openSession(
            model: model,
            addressDraft: browserAddressDraft,
            workspaceRoot: workspaceRoot,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func addBrowserComment(_ comment: String) {
        paneCoordinator.addBrowserComment(comment, to: model)
        refresh()
    }
}
