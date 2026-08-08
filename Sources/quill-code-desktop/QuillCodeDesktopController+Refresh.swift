import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func refresh() {
        progressRefreshScheduler.flush { [weak self] in
            self?.refreshNow()
        }
    }

    func scheduleProgressRefresh() {
        progressRefreshScheduler.schedule { [weak self] in
            self?.refreshNow()
        }
    }

    private func refreshNow() {
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
