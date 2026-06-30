import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopPaneCoordinator {
    func toggleTerminal(on model: QuillCodeWorkspaceModel) {
        model.toggleTerminal()
    }

    func toggleBrowser(on model: QuillCodeWorkspaceModel) {
        model.toggleBrowser()
    }

    func toggleExtensions(on model: QuillCodeWorkspaceModel) {
        model.toggleExtensions()
    }

    func toggleMemories(on model: QuillCodeWorkspaceModel) {
        model.toggleMemories()
    }

    func toggleActivity(on model: QuillCodeWorkspaceModel) {
        model.toggleActivity()
    }

    func toggleAutomations(on model: QuillCodeWorkspaceModel) {
        model.toggleAutomations()
    }

    func addBrowserComment(_ comment: String, to model: QuillCodeWorkspaceModel) {
        _ = model.addBrowserComment(comment)
    }
}
