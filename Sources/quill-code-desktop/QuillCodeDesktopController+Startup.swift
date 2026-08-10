@MainActor
struct QuillCodeDesktopStartupState {
    private(set) var automaticWorkspaceServicesArePaused: Bool
    private(set) var automaticWorkspaceServicesStarted = false

    init(mode: QuillCodeDesktopStartupMode) {
        self.automaticWorkspaceServicesArePaused = mode.pausesAutomaticWorkspaceServices
    }

    mutating func startAutomaticWorkspaceServicesIfAllowed() -> Bool {
        guard !automaticWorkspaceServicesArePaused else { return false }
        guard !automaticWorkspaceServicesStarted else { return false }
        automaticWorkspaceServicesStarted = true
        return true
    }

    mutating func resumeAutomaticWorkspaceServices() -> Bool {
        automaticWorkspaceServicesArePaused = false
        return startAutomaticWorkspaceServicesIfAllowed()
    }
}

@MainActor
extension QuillCodeDesktopController {
    var automaticWorkspaceServicesArePaused: Bool {
        automaticStartupState.automaticWorkspaceServicesArePaused
    }

    var automaticWorkspaceServicesStarted: Bool {
        automaticStartupState.automaticWorkspaceServicesStarted
    }

    /// Crosses the first-window startup boundary. A recovery launch remains in the `.starting`
    /// phase until the user either keeps automatic work paused or deliberately resumes it.
    func completeStartupIfAllowed() {
        guard !automaticWorkspaceServicesArePaused else { return }
        if automaticStartupState.startAutomaticWorkspaceServicesIfAllowed() {
            startAutomaticWorkspaceServices()
        }
        launchLifecycleController?.markReady()
    }

    func continueWithAutomaticWorkspaceServicesPaused() {
        launchLifecycleController?.markReady()
    }

    func resumeAutomaticWorkspaceServices() {
        if automaticStartupState.resumeAutomaticWorkspaceServices() {
            startAutomaticWorkspaceServices()
        }
        launchLifecycleController?.markReady()
    }

    private func startAutomaticWorkspaceServices() {
        model.startAutomaticStartupWork()
        let cuaCoordinator = computerUseCoordinator
        let cuaModel = model
        tasks.replace(.computerUseBackendResolution) {
            await cuaCoordinator.resolvePreferredBackend(on: cuaModel)
            await cuaCoordinator.refreshForegroundApplication(on: cuaModel)
        }
        model.scheduleSelectedProjectContextRefresh()
        // Bootstrap may finish a very small scan before its callback is installed. Starting one
        // final generation here guarantees the published surface receives the completed index.
        model.refreshFileMentionIndex()
        automationCoordinator.runDueAutomations(
            model: model,
            notifier: automationNotifier,
            refresh: { [weak self] in self?.refresh() }
        )
        automationCoordinator.startTicker(
            model: model,
            tasks: tasks,
            notifier: automationNotifier,
            refresh: { [weak self] in self?.refresh() }
        )
        scheduleModelCatalogRefreshIfNeeded()
        modelCatalogRefreshCoordinator.startTicker(tasks: tasks) { [weak self] in
            self?.scheduleModelCatalogRefreshIfNeeded()
        }
        scheduleTrustedRouterCreditsRefreshIfNeeded()
        trustedRouterCreditsCoordinator.startTicker(tasks: tasks) { [weak self] in
            self?.scheduleTrustedRouterCreditsRefreshIfNeeded()
        }
        refresh()
    }
}
