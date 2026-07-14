import Foundation
import QuillCodeApp
import QuillCodeCore

struct QuillCodeDesktopSettingsResult {
    var config: AppConfig
    var runtime: QuillCodeRuntime
    var trustedRouterAPIKeyConfigured: Bool
}

@MainActor
struct QuillCodeDesktopSettingsCoordinator {
    private let bootstrap: QuillCodeWorkspaceBootstrap

    init(bootstrap: QuillCodeWorkspaceBootstrap) {
        self.bootstrap = bootstrap
    }

    func setMode(_ mode: AgentMode, on model: QuillCodeWorkspaceModel) {
        model.setMode(mode)
        persist(model.root.config)
    }

    func setModel(_ modelID: String, on model: QuillCodeWorkspaceModel) {
        model.setModel(modelID)
        persist(model.root.config)
    }

    func toggleModelFavorite(_ modelID: String, on model: QuillCodeWorkspaceModel) {
        model.toggleModelFavorite(modelID)
        persist(model.root.config)
    }

    func setKeyboardShortcutPreferences(
        _ preferences: KeyboardShortcutPreferences,
        on model: QuillCodeWorkspaceModel
    ) {
        model.setKeyboardShortcutPreferences(preferences)
        persist(model.root.config)
    }

    func refreshModelCatalog(on model: QuillCodeWorkspaceModel) async {
        let catalog = await bootstrap.fetchModelCatalog(config: model.root.config)
        model.setModelCatalog(catalog)
    }

    func saveSettings(
        _ update: WorkspaceSettingsUpdate,
        to model: QuillCodeWorkspaceModel,
        refresh: @escaping @MainActor () -> Void
    ) {
        let result = apply(
            update: update,
            currentConfig: model.root.config
        )
        model.applySettings(
            config: result.config,
            trustedRouterAPIKeyConfigured: result.trustedRouterAPIKeyConfigured
        )
        model.applyRuntime(result.runtime)
        refresh()
        Task { @MainActor in
            await refreshModelCatalog(on: model)
            refresh()
        }
    }

    func persist(_ config: AppConfig) {
        try? bootstrap.saveConfig(config)
    }

    func apply(
        update: WorkspaceSettingsUpdate,
        currentConfig: AppConfig
    ) -> QuillCodeDesktopSettingsResult {
        var config = currentConfig
        config.apiBaseURL = update.apiBaseURL
        config.authMode = update.authMode
        config.developerOverrideEnabled = update.developerOverrideEnabled || update.authMode == .developerOverride
        config.computerUseApprovedBundleIdentifiers = update.computerUseApprovedBundleIdentifiers
        config.computerUseApprovedAppNames = update.computerUseApprovedAppNames
        config.browserAllowedDomains = update.browserAllowedDomains
        config.browserBlockedDomains = update.browserBlockedDomains
        config.notificationPreferences = update.notificationPreferences
        config.runSpendFuseUSD = update.runSpendFuseUSD
        config.runSpendPeriodLimits = update.runSpendPeriodLimits
        config.managedWorktrees = update.managedWorktrees

        if update.shouldClearAPIKey {
            try? bootstrap.clearTrustedRouterAPIKey()
            config.trustedRouterAccount = nil
        }
        if let replacementAPIKey = update.replacementAPIKey {
            try? bootstrap.saveTrustedRouterAPIKey(replacementAPIKey)
            config.trustedRouterAccount = nil
        }
        if config.authMode == .developerOverride {
            config.trustedRouterAccount = nil
        }

        return persistAndBuildResult(config)
    }

    func result(for config: AppConfig) -> QuillCodeDesktopSettingsResult {
        persistAndBuildResult(config)
    }

    private func persistAndBuildResult(_ config: AppConfig) -> QuillCodeDesktopSettingsResult {
        try? bootstrap.saveConfig(config)
        return QuillCodeDesktopSettingsResult(
            config: config,
            runtime: bootstrap.makeRuntime(config: config),
            trustedRouterAPIKeyConfigured: bootstrap.hasTrustedRouterAPIKey()
        )
    }
}
