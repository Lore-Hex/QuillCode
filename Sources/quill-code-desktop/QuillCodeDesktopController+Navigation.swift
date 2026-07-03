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
        refresh()
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
