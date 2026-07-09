import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopNavigationCoordinator {
    func newChat(model: QuillCodeWorkspaceModel) {
        _ = model.newChat()
    }

    func selectThread(_ id: UUID, model: QuillCodeWorkspaceModel) {
        model.selectThread(id)
    }

    func runThreadAction(
        _ mutation: WorkspaceThreadRowMutation,
        model: QuillCodeWorkspaceModel
    ) {
        WorkspaceSidebarRowMutationExecutor.execute(mutation, model: model)
    }

    @discardableResult
    func renameThread(
        _ id: UUID,
        title: String,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        model.renameThread(id, to: title)
    }

    func selectProject(_ id: UUID?, model: QuillCodeWorkspaceModel) {
        model.selectProject(id)
    }

    func runProjectAction(
        _ mutation: WorkspaceProjectRowMutation,
        model: QuillCodeWorkspaceModel
    ) {
        WorkspaceSidebarRowMutationExecutor.execute(mutation, model: model)
    }

    @discardableResult
    func moveProject(
        _ sourceID: UUID,
        before targetID: UUID,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        model.moveProject(sourceID, before: targetID)
    }

    @discardableResult
    func renameProject(
        _ id: UUID,
        name: String,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        model.renameProject(id, to: name)
    }

    func addProject(_ url: URL, model: QuillCodeWorkspaceModel) {
        _ = model.addProject(path: url)
    }
}
