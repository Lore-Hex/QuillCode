import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func refresh() {
        progressRefreshScheduler.flush { [weak self] in
            self?.refreshNow(progressScope: nil)
        }
    }

    func scheduleProgressRefresh(_ scope: WorkspaceProgressSurfaceScope) {
        progressRefreshScheduler.schedule(scope) { [weak self] coalescedScope in
            self?.refreshNow(progressScope: coalescedScope)
        }
    }

    private func refreshNow(progressScope: WorkspaceProgressSurfaceScope?) {
        var nextSurface = surface
        var nextDraft = draft
        var nextTerminalDraft = terminalDraft
        var nextBrowserAddressDraft = browserAddressDraft
        let isComposerTaskRunning = tasks.isSendRunning(threadID: model.selectedThread?.id)
        if let progressScope {
            modelStateCoordinator.refreshProgressState(
                from: model,
                scope: progressScope,
                surface: &nextSurface,
                draft: &nextDraft,
                terminalDraft: &nextTerminalDraft,
                browserAddressDraft: &nextBrowserAddressDraft,
                isComposerTaskRunning: isComposerTaskRunning
            )
        } else {
            modelStateCoordinator.refreshState(
                from: model,
                surface: &nextSurface,
                draft: &nextDraft,
                terminalDraft: &nextTerminalDraft,
                browserAddressDraft: &nextBrowserAddressDraft,
                isComposerTaskRunning: isComposerTaskRunning
            )
        }
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

    func scheduleModelCatalogRefreshIfNeeded() {
        tasks.startIfIdle(.modelCatalogRefresh) { [weak self] in
            guard let self else { return }
            await modelCatalogRefreshCoordinator.refreshIfNeeded(
                on: model,
                refresh: { [weak self] in self?.refresh() }
            )
        }
    }

    func scheduleTrustedRouterCreditsRefreshIfNeeded() {
        tasks.startIfIdle(.trustedRouterCreditsRefresh) { [weak self] in
            guard let self else { return }
            await trustedRouterCreditsCoordinator.refresh(
                on: model,
                refreshSurface: { [weak self] in self?.refresh() }
            )
        }
    }
}
