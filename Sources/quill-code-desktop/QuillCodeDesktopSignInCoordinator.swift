import AppKit
import Foundation
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore

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
        let server = try TrustedRouterLoopbackCallbackServer()
        try await server.start()
        defer { server.cancel() }

        let authorization = try client.createAuthorization(
            callbackURL: TrustedRouterLoopbackCallbackServer.callbackURL,
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
        config.trustedRouterAccount = await accountProfile(from: token, client: client)

        try bootstrap.saveTrustedRouterAPIKey(token.key)
        try bootstrap.saveConfig(config)
        return QuillCodeDesktopSignInResult(
            config: config,
            trustedRouterAPIKeyConfigured: true
        )
    }

    private func accountProfile(
        from token: TrustedRouterOAuthToken,
        client: TrustedRouterOAuthClient
    ) async -> TrustedRouterAccountProfile? {
        var profile = TrustedRouterAccountProfile(
            userID: token.userID,
            subject: token.identity?.sub,
            email: token.identity?.email,
            walletAddress: token.identity?.walletAddress
        )
        if let userInfo = try? await client.fetchUserInfo(apiKey: token.key) {
            profile = TrustedRouterAccountProfile(
                userID: profile.userID,
                subject: profile.subject ?? userInfo.data.sub,
                email: profile.email ?? userInfo.data.email,
                walletAddress: profile.walletAddress ?? userInfo.data.walletAddress
            )
        }
        return profile.isEmpty ? nil : profile
    }
}
