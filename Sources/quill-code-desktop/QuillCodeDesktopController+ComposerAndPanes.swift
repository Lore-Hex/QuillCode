import Foundation
import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func send() {
        if composerCoordinator.openBrowserSessionFromSlashIfNeeded(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() },
            openVisibleBrowserSession: { [weak self] in self?.openBrowserSession() }
        ) {
            return
        }
        composerCoordinator.send(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() },
            onSlotFree: { [weak self] in self?.recoverSelectedThreadDrain() }
        )
    }

    func retryLastTurn() {
        composerCoordinator.retryLastTurn(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() },
            onSlotFree: { [weak self] in self?.recoverSelectedThreadDrain() }
        )
    }

    func stopWorkflowRecording() {
        workflowRecordingCoordinator.stopAndCreateSkill(
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() },
            onSlotFree: { [weak self] in self?.recoverSelectedThreadDrain() }
        )
    }

    func requestAddImages() {
        isImageImporterPresented = true
    }

    func removeComposerImage(_ id: UUID) {
        model.removeComposerImage(id)
        refresh()
    }

    func handleImageImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            Task { @MainActor [weak self] in
                guard let self else { return }
                let securityScopes = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
                defer {
                    for (url, didStart) in securityScopes where didStart {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                await model.addComposerImages(from: urls)
                refresh()
            }
        case .failure(let error):
            model.reportImageAttachmentError(error)
            refresh()
        }
    }

    /// Recovers the currently-selected thread's stranded follow-up queue once the `.send` slot frees
    /// (a send/approval finished). Covers the case where the user denied thread A's gate while a
    /// send ran on thread B in the background: B's completion frees the slot and this drains A.
    private func recoverSelectedThreadDrain() {
        recoverFollowUpDrain(for: model.selectedThread?.id)
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
