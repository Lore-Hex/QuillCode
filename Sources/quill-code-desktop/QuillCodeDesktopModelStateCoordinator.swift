import Foundation
import QuillCodeApp

struct QuillCodeDesktopModelState {
    let surface: WorkspaceSurface
    let draft: String
    let terminalDraft: String
    let browserAddressDraft: String
}

@MainActor
struct QuillCodeDesktopModelStateCoordinator {
    func ensureDefaultProject(on model: QuillCodeWorkspaceModel, workspaceRoot: URL) {
        if model.root.projects.isEmpty {
            _ = model.addProject(path: workspaceRoot)
        }
    }

    func initialState(from model: QuillCodeWorkspaceModel) -> QuillCodeDesktopModelState {
        QuillCodeDesktopModelState(
            surface: model.surface(),
            draft: model.composer.draft,
            terminalDraft: model.terminal.draft,
            browserAddressDraft: model.browser.addressDraft
        )
    }

    func refreshState(
        from model: QuillCodeWorkspaceModel,
        surface: inout WorkspaceSurface,
        draft: inout String,
        terminalDraft: inout String,
        browserAddressDraft: inout String,
        isComposerTaskRunning: Bool = false
    ) {
        let nextState = initialState(from: model)
        let isComposerBusy = model.composer.isSending || isComposerTaskRunning
        surface = nextState.surface

        if draft != nextState.draft, !isComposerBusy {
            draft = nextState.draft
        }
        surface.composer = ComposerSurface(composer: ComposerState(
            draft: draft,
            isSending: isComposerBusy,
            placeholder: nextState.surface.composer.placeholder
        ))
        if terminalDraft != nextState.terminalDraft, !model.terminal.isRunning {
            terminalDraft = nextState.terminalDraft
        }
        if browserAddressDraft != nextState.browserAddressDraft {
            browserAddressDraft = nextState.browserAddressDraft
        }
    }

    func syncComposerDraft(from model: QuillCodeWorkspaceModel, draft: inout String) {
        draft = model.composer.draft
    }
}
