import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func refresh() {
        computerUseCoordinator.refreshStatus(on: model)
        var nextSurface = surface
        var nextDraft = draft
        var nextTerminalDraft = terminalDraft
        var nextBrowserAddressDraft = browserAddressDraft
        modelStateCoordinator.refreshState(
            from: model,
            surface: &nextSurface,
            draft: &nextDraft,
            terminalDraft: &nextTerminalDraft,
            browserAddressDraft: &nextBrowserAddressDraft,
            isComposerTaskRunning: tasks.isSendRunning(threadID: model.selectedThread?.id)
        )
        if nextSurface != surface {
            surface = nextSurface
        }
        if nextDraft != draft {
            draft = nextDraft
        }
        if nextTerminalDraft != terminalDraft {
            terminalDraft = nextTerminalDraft
        }
        if nextBrowserAddressDraft != browserAddressDraft {
            browserAddressDraft = nextBrowserAddressDraft
        }
    }

    func requestProgressRefresh() {
        progressRefreshScheduler.request { [weak self] in
            self?.refresh()
        }
    }

    func refreshImmediatelyAfterProgress() {
        progressRefreshScheduler.cancelPending()
        refresh()
    }
}
