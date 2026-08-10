import Foundation
import QuillCodeApp
import QuillCodeCore

struct QuillCodeDesktopSettingsResult {
    var config: AppConfig
    var runtime: QuillCodeRuntime
    var trustedRouterAPIKeyConfigured: Bool
    var persistedKinds: Set<WorkspaceSettingsPersistenceKind>
}

@MainActor
struct QuillCodeDesktopSettingsCoordinator {
    private let bootstrap: QuillCodeWorkspaceBootstrap

    init(bootstrap: QuillCodeWorkspaceBootstrap) {
        self.bootstrap = bootstrap
    }

    func setMode(_ mode: AgentMode, on model: QuillCodeWorkspaceModel) {
        model.setMode(mode)
        persist(model.root.config, on: model)
    }

    func setModel(_ modelID: String, on model: QuillCodeWorkspaceModel) {
        model.setModel(modelID)
        persist(model.root.config, on: model)
    }

    func toggleModelFavorite(_ modelID: String, on model: QuillCodeWorkspaceModel) {
        model.toggleModelFavorite(modelID)
        persist(model.root.config, on: model)
    }

    func setKeyboardShortcutPreferences(
        _ preferences: KeyboardShortcutPreferences,
        on model: QuillCodeWorkspaceModel
    ) {
        model.setKeyboardShortcutPreferences(preferences)
        persist(model.root.config, on: model)
    }

    func setRunSpendFuseUSD(_ value: Double?, on model: QuillCodeWorkspaceModel) {
        let previousValue = model.root.config.runSpendFuseUSD
        model.setRunSpendFuseUSD(value)
        do {
            try bootstrap.saveConfig(model.root.config)
            model.recordSettingsPersistenceSuccess([.configuration])
        } catch {
            model.setRunSpendFuseUSD(previousValue)
            model.recordSettingsPersistenceFailure([.configuration])
        }
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
        let currentConfig = model.root.config
        let appliedResult: QuillCodeDesktopSettingsResult
        do {
            appliedResult = try apply(
                update: update,
                currentConfig: currentConfig
            )
            model.recordSettingsPersistenceSuccess(appliedResult.persistedKinds)
        } catch let error as WorkspaceSettingsPersistenceError {
            model.recordSettingsPersistenceFailure(error.failedKinds)
            let currentResult = result(for: currentConfig)
            model.applySettings(
                config: currentResult.config,
                trustedRouterAPIKeyConfigured: currentResult.trustedRouterAPIKeyConfigured
            )
            model.applyRuntime(currentResult.runtime)
            refresh()
            return
        } catch {
            model.recordSettingsPersistenceFailure([.configuration])
            refresh()
            return
        }
        model.applySettings(
            config: appliedResult.config,
            trustedRouterAPIKeyConfigured: appliedResult.trustedRouterAPIKeyConfigured
        )
        model.applyRuntime(appliedResult.runtime)
        refresh()
        Task { @MainActor in
            await refreshModelCatalog(on: model)
            refresh()
        }
    }

    func persist(_ config: AppConfig, on model: QuillCodeWorkspaceModel) {
        do {
            try bootstrap.saveConfig(config)
            model.recordSettingsPersistenceSuccess([.configuration])
        } catch {
            model.recordSettingsPersistenceFailure([.configuration])
        }
    }

    func apply(
        update: WorkspaceSettingsUpdate,
        currentConfig: AppConfig
    ) throws -> QuillCodeDesktopSettingsResult {
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
        config.reviewModel = update.reviewModel
        config.reviewDelivery = update.reviewDelivery
        config.defaultPersonality = update.defaultPersonality

        let credentialMutation: WorkspaceTrustedRouterCredentialMutation
        if let replacementAPIKey = update.replacementAPIKey {
            credentialMutation = .replace(replacementAPIKey)
            config.trustedRouterAccount = nil
        } else if update.shouldClearAPIKey {
            credentialMutation = .clear
            config.trustedRouterAccount = nil
        } else {
            credentialMutation = .unchanged
        }
        if config.authMode == .developerOverride {
            config.trustedRouterAccount = nil
        }

        do {
            try bootstrap.saveSettingsTransaction(
                currentConfig: currentConfig,
                proposedConfig: config,
                credentialMutation: credentialMutation
            )
        } catch let error as WorkspaceSettingsPersistenceError {
            throw error
        } catch {
            var kinds: Set<WorkspaceSettingsPersistenceKind> = [.configuration]
            if credentialMutation.changesCredential {
                kinds.insert(.trustedRouterCredential)
            }
            throw WorkspaceSettingsPersistenceError(
                failedKinds: kinds,
                rollbackFailed: true
            )
        }
        var persistedKinds: Set<WorkspaceSettingsPersistenceKind> = [.configuration]
        if credentialMutation.changesCredential {
            persistedKinds.insert(.trustedRouterCredential)
        }
        return result(for: config, persistedKinds: persistedKinds)
    }

    func result(for config: AppConfig) -> QuillCodeDesktopSettingsResult {
        result(for: config, persistedKinds: [])
    }

    private func result(
        for config: AppConfig,
        persistedKinds: Set<WorkspaceSettingsPersistenceKind>
    ) -> QuillCodeDesktopSettingsResult {
        return QuillCodeDesktopSettingsResult(
            config: config,
            runtime: bootstrap.makeRuntime(config: config),
            trustedRouterAPIKeyConfigured: bootstrap.hasTrustedRouterAPIKey(),
            persistedKinds: persistedKinds
        )
    }
}
