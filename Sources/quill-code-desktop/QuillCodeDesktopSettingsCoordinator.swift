import Foundation
import QuillCodeApp
import QuillCodeCore

struct QuillCodeDesktopSettingsResult {
    var config: AppConfig
    var runtime: QuillCodeRuntime
    var trustedRouterAPIKeyConfigured: Bool
}

struct QuillCodeDesktopSettingsCoordinator {
    private let bootstrap: QuillCodeWorkspaceBootstrap

    init(bootstrap: QuillCodeWorkspaceBootstrap) {
        self.bootstrap = bootstrap
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
