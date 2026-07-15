import AppKit
import Foundation
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillCodePlatform

struct QuillCodeDesktopSignInResult {
    var config: AppConfig
    var trustedRouterAPIKeyConfigured: Bool
}

@MainActor
struct QuillCodeDesktopSignInCoordinator {
    var bootstrap: QuillCodeWorkspaceBootstrap
    var openURL: (URL) -> Void

    init(
        bootstrap: QuillCodeWorkspaceBootstrap,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.bootstrap = bootstrap
        self.openURL = openURL
    }

    func completeSignIn(
        currentConfig: AppConfig,
        status: @escaping @MainActor (_ label: String, _ error: String?) -> Void
    ) async throws -> QuillCodeDesktopSignInResult {
        status("Opening TrustedRouter", nil)
        let client = try TrustedRouterOAuthClient(baseURL: currentConfig.apiBaseURL)
        guard let configuredCallbackURL = URL(
            string: TrustedRouterDefaults.loopbackCallbackURL
        ) else {
            throw TrustedRouterOAuthError.invalidCallbackURL(TrustedRouterDefaults.loopbackCallbackURL)
        }
        let server = try LoopbackHTTPCallbackServer(callbackURL: configuredCallbackURL)
        defer { server.cancel() }

        let authorization = try client.createAuthorization(
            callbackURL: server.callbackURL.absoluteString,
            keyLabel: "QuillCode"
        )
        openURL(authorization.url)
        status("Waiting for TrustedRouter", nil)

        let callbackURL = try await server.waitForCallback()
        status("Finishing sign-in", nil)
        let code = try client.parseCallback(callbackURL, expectedState: authorization.state)
        let token = try await client.exchangeCode(
            code: code,
            codeVerifier: authorization.codeVerifier
        )

        var config = currentConfig
        config.authMode = .oauth
        config.developerOverrideEnabled = false
        config.trustedRouterAccount = await client.accountProfile(from: token)

        try bootstrap.saveTrustedRouterAPIKey(token.key)
        try bootstrap.saveConfig(config)
        return QuillCodeDesktopSignInResult(
            config: config,
            trustedRouterAPIKeyConfigured: true
        )
    }

    func completeSignInAndApply(
        to model: QuillCodeWorkspaceModel,
        settingsCoordinator: QuillCodeDesktopSettingsCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) async {
        do {
            let result = try await completeSignIn(
                currentConfig: model.root.config
            ) { label, error in
                model.setAgentStatus(label, lastError: error)
                refresh()
            }
            applySignInResult(result, to: model, settingsCoordinator: settingsCoordinator)
            refresh()
            let catalog = await bootstrap.fetchModelCatalog(config: model.root.config)
            model.setModelCatalog(catalog)
            refresh()
        } catch {
            model.setAgentStatus(
                QuillCodeRuntimeStatusLabel.signInFailed,
                lastError: String(describing: error)
            )
            refresh()
        }
    }

    private func applySignInResult(
        _ result: QuillCodeDesktopSignInResult,
        to model: QuillCodeWorkspaceModel,
        settingsCoordinator: QuillCodeDesktopSettingsCoordinator
    ) {
        let settings = settingsCoordinator.result(for: result.config)
        model.applySettings(
            config: settings.config,
            trustedRouterAPIKeyConfigured: settings.trustedRouterAPIKeyConfigured
        )
        model.applyRuntime(settings.runtime)
    }
}
