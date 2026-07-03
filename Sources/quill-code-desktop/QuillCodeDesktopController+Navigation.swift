import Foundation
import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func newChat() {
        // Stash the live draft to the outgoing thread before opening a new chat.
        model.setDraft(draft)
        navigationCoordinator.newChat(model: model)
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        refresh()
    }

    func selectThread(_ id: UUID) {
        // Persist the live in-progress draft to the outgoing thread before switching
        // so the model can stash it and restore the incoming thread's draft.
        model.setDraft(draft)
        navigationCoordinator.selectThread(id, model: model)
        // Force-sync the restored draft even mid-send (the busy gate would otherwise
        // keep the old thread's text visible under the newly selected thread).
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        // Recover a follow-up queue that was stranded because its thread was decided/finished while
        // the single `.send` slot was busy on another thread (a cross-thread deny). Selecting the
        // thread makes it the active context, so drain it now if idle (self-gated: a no-op while a
        // run is in flight or an approval is still undecided on it).
        recoverFollowUpDrain(for: id)
        refresh()
    }

    /// Drains a thread's stranded follow-up queue through the `.send` slot when it becomes idle/active
    /// again (thread select, or a send/approval freeing the slot). `recoverFollowUpQueueIfIdle`
    /// self-gates, so this is a safe no-op when there is nothing to recover. `threadID` is the
    /// selected thread here, so the cheap `followUpQueue.isEmpty` pre-check avoids churning the
    /// `.send` slot on the common case of selecting a thread with nothing queued.
    func recoverFollowUpDrain(for threadID: UUID?) {
        guard threadID != nil, threadID == model.selectedThread?.id, !model.followUpQueue.isEmpty else { return }
        let root = model.activeWorkspaceRoot ?? workspaceRoot
        tasks.startIfIdle(.send) { [weak self] in
            await self?.model.recoverFollowUpQueueIfIdle(threadID: threadID, workspaceRoot: root)
        } onFinish: { [weak self] in
            self?.refresh()
        }
    }

    func runThreadAction(_ mutation: WorkspaceThreadRowMutation) {
        // Stash the live draft before a row action (duplicate/archive/delete) that
        // may change the selected thread, then force-sync the restored draft.
        model.setDraft(draft)
        navigationCoordinator.runThreadAction(mutation, model: model)
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        refresh()
    }

    func renameThread(_ id: UUID, title: String) {
        _ = navigationCoordinator.renameThread(id, title: title, model: model)
        refresh()
    }

    func saveSidebarSavedSearch(title: String, query: String) {
        _ = model.saveSidebarSavedSearch(title: title, query: query)
        refresh()
    }

    func selectProject(_ id: UUID?) {
        navigationCoordinator.selectProject(id, model: model)
        refresh()
    }

    func runProjectAction(_ mutation: WorkspaceProjectRowMutation) {
        navigationCoordinator.runProjectAction(mutation, model: model)
        refresh()
    }

    func renameProject(_ id: UUID, name: String) {
        _ = navigationCoordinator.renameProject(id, name: name, model: model)
        refresh()
    }

    func requestAddProject() {
        isProjectImporterPresented = true
    }

    func handleProjectImport(_ result: Result<[URL], Error>) {
        guard let selection = projectImportCoordinator.selectedProject(from: result) else {
            return
        }
        addProject(selection.url)
    }

    func addProject(_ url: URL) {
        navigationCoordinator.addProject(url, model: model)
        refresh()
    }
}
