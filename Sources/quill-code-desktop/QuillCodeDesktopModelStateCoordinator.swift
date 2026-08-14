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
            _ = model.registerProject(path: workspaceRoot)
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
        reconcile(
            nextState,
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft,
            updatesComposer: true,
            updatesTerminal: true,
            updatesBrowser: true,
            isComposerTaskRunning: isComposerTaskRunning
        )
    }

    func refreshProgressState(
        from model: QuillCodeWorkspaceModel,
        scope: WorkspaceProgressSurfaceScope,
        surface: inout WorkspaceSurface,
        draft: inout String,
        terminalDraft: inout String,
        browserAddressDraft: inout String,
        isComposerTaskRunning: Bool = false
    ) {
        let nextState = QuillCodeDesktopModelState(
            surface: model.progressSurface(reusing: surface, scope: scope),
            draft: model.composer.draft,
            terminalDraft: model.terminal.draft,
            browserAddressDraft: model.browser.addressDraft
        )
        reconcile(
            nextState,
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft,
            updatesComposer: scope.contains(.agent),
            updatesTerminal: scope.contains(.terminal),
            updatesBrowser: scope.contains(.agent),
            isComposerTaskRunning: isComposerTaskRunning
        )
    }

    private func reconcile(
        _ nextState: QuillCodeDesktopModelState,
        from model: QuillCodeWorkspaceModel,
        surface: inout WorkspaceSurface,
        draft: inout String,
        terminalDraft: inout String,
        browserAddressDraft: inout String,
        updatesComposer: Bool,
        updatesTerminal: Bool,
        updatesBrowser: Bool,
        isComposerTaskRunning: Bool
    ) {
        let isComposerBusy = model.composer.isSending || isComposerTaskRunning
        surface = nextState.surface

        if updatesComposer, draft != nextState.draft, !isComposerBusy {
            draft = nextState.draft
        }
        // Rebuild from the LOCAL draft so slash/@-mention suggestions reflect live typing, but
        // carry EVERY model-derived field the bare rebuild would otherwise silently drop: the
        // focusToken (focus-composer's signal — without it Cmd+L is dead on native because the
        // view's .onChange never fires), the file-mention index + changed paths (so @-mentions
        // aren't computed against an empty index), the sent-message history (Up/Down recall), the
        // live plan-progress strip + queued follow-up chips (the unattended-driving check-in surface
        // — otherwise both vanish on every controller-triggered refresh), and supportsPersonality
        // (drives whether personality slash suggestions appear; defaulting it true after a refresh
        // would surface `/personality` on models that don't support it).
        if updatesComposer {
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
                sentMessageHistory: nextState.surface.composer.sentMessageHistory,
                planProgress: nextState.surface.composer.planProgress,
                followUpQueue: model.selectedThread?.followUpQueue ?? [],
                supportsPersonality: nextState.surface.composer.supportsPersonality
            )
        }
        if updatesTerminal, terminalDraft != nextState.terminalDraft, !model.terminal.isRunning {
            terminalDraft = nextState.terminalDraft
        }
        if updatesBrowser, browserAddressDraft != nextState.browserAddressDraft {
            browserAddressDraft = nextState.browserAddressDraft
        }
    }

    func syncComposerDraft(from model: QuillCodeWorkspaceModel, draft: inout String) {
        draft = model.composer.draft
    }
}
