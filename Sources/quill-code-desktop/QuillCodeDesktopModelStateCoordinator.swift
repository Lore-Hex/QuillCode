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
        // Rebuild from the LOCAL draft so slash/@-mention suggestions reflect live typing, but
        // carry the model-derived fields the bare rebuild used to silently drop: the focusToken
        // (focus-composer's signal — without it Cmd+L is dead on native because the view's
        // .onChange never fires), the file-mention index + changed paths (so @-mentions aren't
        // computed against an empty index), and the sent-message history (Up/Down recall).
        surface.composer = ComposerSurface(
            composer: ComposerState(
                draft: draft,
                attachments: model.composer.attachments,
                isSending: isComposerBusy,
                placeholder: nextState.surface.composer.placeholder,
                focusToken: model.composer.focusToken
            ),
            fileMentionIndex: model.fileMentionIndex,
            changedFilePaths: nextState.surface.changedFilePaths,
            sentMessageHistory: nextState.surface.composer.sentMessageHistory
        )
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
