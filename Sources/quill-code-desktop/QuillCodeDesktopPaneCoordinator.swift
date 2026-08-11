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

    func toggleExtensions(on model: QuillCodeWorkspaceModel, surface: inout WorkspaceSurface) {
        model.toggleExtensions()
        surface = model.panePresentationSurface(reusing: surface, scope: .extensions)
    }

    func toggleMemories(on model: QuillCodeWorkspaceModel, surface: inout WorkspaceSurface) {
        model.toggleMemories()
        surface = model.panePresentationSurface(reusing: surface, scope: .memories)
    }

    func toggleActivity(on model: QuillCodeWorkspaceModel, surface: inout WorkspaceSurface) {
        model.toggleActivity()
        surface = model.panePresentationSurface(reusing: surface, scope: .activity)
    }

    func toggleAutomations(on model: QuillCodeWorkspaceModel, surface: inout WorkspaceSurface) {
        model.toggleAutomations()
        surface = model.panePresentationSurface(reusing: surface, scope: .automations)
    }

    func addBrowserComment(_ comment: String, to model: QuillCodeWorkspaceModel) {
        _ = model.addBrowserComment(comment)
    }
}
