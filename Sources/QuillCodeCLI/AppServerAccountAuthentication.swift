import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodePlatform

struct AppServerAccountCredential: Sendable {
    var apiKey: String
    var profile: TrustedRouterAccountProfile?
}

struct AppServerAccountBrowserLogin: Sendable {
    var authURL: URL
    var waitForCredential: @Sendable () async throws -> AppServerAccountCredential
    var cancel: @Sendable () -> Void
}

protocol AppServerAccountLoginStarting: Sendable {
    func start(baseURL: String) throws -> AppServerAccountBrowserLogin
}

struct DefaultAppServerAccountLoginStarter: AppServerAccountLoginStarting {
    static var trustedRouterCallbackURL: URL {
        get throws {
            guard let url = URL(string: TrustedRouterDefaults.loopbackCallbackURL) else {
                throw TrustedRouterOAuthError.invalidCallbackURL(
                    TrustedRouterDefaults.loopbackCallbackURL
                )
            }
            return url
        }
    }

    func start(baseURL: String) throws -> AppServerAccountBrowserLogin {
        let client = try TrustedRouterOAuthClient(baseURL: baseURL)
        let callbackURL = try Self.trustedRouterCallbackURL
        let callbackServer = try LoopbackHTTPCallbackServer(callbackURL: callbackURL)
        let authorization = try client.createAuthorization(
            callbackURL: callbackServer.callbackURL.absoluteString,
            keyLabel: "QuillCode app-server"
        )
        return AppServerAccountBrowserLogin(
            authURL: authorization.url,
            waitForCredential: {
                defer { callbackServer.cancel() }
                let callback = try await callbackServer.waitForCallback()
                let code = try client.parseCallback(callback, expectedState: authorization.state)
                let token = try await client.exchangeCode(
                    code: code,
                    codeVerifier: authorization.codeVerifier
                )
                return AppServerAccountCredential(
                    apiKey: token.key,
                    profile: await client.accountProfile(from: token)
                )
            },
            cancel: { callbackServer.cancel() }
        )
    }
}

struct AppServerPendingAccountLogin: Sendable {
    var operation: AppServerAccountBrowserLogin
    var task: Task<Void, Never>?
}

struct AppServerAccountRPCOutcome: Sendable {
    var result: CLIJSONValue
    var afterResponse: AppServerAccountAfterResponse?
}

enum AppServerAccountAfterResponse: Sendable {
    case notifications([AppServerAccountNotification])
    case launch(loginID: String)
}

struct AppServerAccountNotification: Sendable {
    var method: String
    var params: CLIJSONValue
}

extension AppServerSession {
    func startAccountLogin(_ raw: CLIJSONValue) throws -> AppServerAccountRPCOutcome {
        let params = try AppServerParams(raw)
        let type = try params.requiredString("type")
        switch type {
        case "apiKey":
            let apiKey = try params.requiredString("apiKey")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try persistAccount(apiKey: apiKey, profile: nil, authMode: .developerOverride)
            return AppServerAccountRPCOutcome(
                result: .object(["type": .string("apiKey")]),
                afterResponse: .notifications(successNotifications(loginID: nil))
            )
        case "chatgpt", "trustedRouter":
            _ = try params.optionalBool("codexStreamlinedLogin")
            let loginID = UUID().uuidString.lowercased()
            let operation: AppServerAccountBrowserLogin
            do {
                operation = try accountLoginStarter.start(baseURL: effectiveAccountBaseURL)
            } catch {
                throw AppServerRPCError.internalError(
                    "Could not start TrustedRouter sign-in: \(accountErrorDescription(error))"
                )
            }
            pendingAccountLogins[loginID] = AppServerPendingAccountLogin(
                operation: operation,
                task: nil
            )
            return AppServerAccountRPCOutcome(
                result: .object([
                    "type": .string(type == "trustedRouter" ? "trustedRouter" : "chatgpt"),
                    "loginId": .string(loginID),
                    "authUrl": .string(operation.authURL.absoluteString)
                ]),
                afterResponse: .launch(loginID: loginID)
            )
        case "chatgptDeviceCode":
            throw AppServerRPCError.invalidParams(
                "chatgptDeviceCode is unavailable because TrustedRouter uses browser OAuth"
            )
        default:
            throw AppServerRPCError.invalidParams(
                "type must be apiKey, chatgpt, or trustedRouter"
            )
        }
    }

    func cancelAccountLogin(_ raw: CLIJSONValue) throws -> AppServerAccountRPCOutcome {
        let loginID = try AppServerParams(raw).requiredString("loginId")
        guard let pending = pendingAccountLogins.removeValue(forKey: loginID) else {
            return AppServerAccountRPCOutcome(
                result: .object(["status": .string("notFound")]),
                afterResponse: nil
            )
        }
        pending.operation.cancel()
        pending.task?.cancel()
        return AppServerAccountRPCOutcome(
            result: .object(["status": .string("canceled")]),
            afterResponse: .notifications([
                loginCompletedNotification(
                    loginID: loginID,
                    success: false,
                    error: "TrustedRouter sign-in was cancelled."
                )
            ])
        )
    }

    func logoutAccount(_ raw: CLIJSONValue) throws -> AppServerAccountRPCOutcome {
        try AppServerDiscoveryParams.requireEmpty(raw, method: "account/logout")
        try persistAccount(apiKey: nil, profile: nil, authMode: .oauth)
        return AppServerAccountRPCOutcome(
            result: .object([:]),
            afterResponse: .notifications([accountUpdatedNotification()])
        )
    }

    func performAccountAfterResponse(_ action: AppServerAccountAfterResponse) async {
        switch action {
        case .notifications(let notifications):
            await sendAccountNotifications(notifications)
        case .launch(let loginID):
            launchAccountLogin(loginID)
        }
    }

    func cancelAllAccountLogins() {
        let pending = pendingAccountLogins.values
        pendingAccountLogins.removeAll(keepingCapacity: false)
        for login in pending {
            login.operation.cancel()
            login.task?.cancel()
        }
    }

    private var effectiveAccountBaseURL: String {
        let override = request.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? appConfig.apiBaseURL : override
    }

    private func launchAccountLogin(_ loginID: String) {
        guard var pending = pendingAccountLogins[loginID], pending.task == nil else { return }
        let operation = pending.operation
        pending.task = Task { [self] in
            do {
                let credential = try await operation.waitForCredential()
                await completeAccountLogin(loginID: loginID, result: .success(credential))
            } catch {
                await completeAccountLogin(loginID: loginID, result: .failure(error))
            }
        }
        pendingAccountLogins[loginID] = pending
    }

    private func completeAccountLogin(
        loginID: String,
        result: Result<AppServerAccountCredential, Error>
    ) async {
        guard pendingAccountLogins.removeValue(forKey: loginID) != nil, !inputFinished else { return }
        switch result {
        case .success(let credential):
            do {
                try persistAccount(
                    apiKey: credential.apiKey,
                    profile: credential.profile,
                    authMode: .oauth
                )
                await sendAccountNotifications(successNotifications(loginID: loginID))
            } catch {
                await sendAccountNotifications([
                    loginCompletedNotification(
                        loginID: loginID,
                        success: false,
                        error: "Could not save TrustedRouter sign-in: \(accountErrorDescription(error))"
                    )
                ])
            }
        case .failure(let error):
            await sendAccountNotifications([
                loginCompletedNotification(
                    loginID: loginID,
                    success: false,
                    error: accountErrorDescription(error)
                )
            ])
        }
    }

    private func persistAccount(
        apiKey: String?,
        profile: TrustedRouterAccountProfile?,
        authMode: TrustedRouterAuthMode
    ) throws {
        let secretStore = FileSecretStore(directory: paths.secretsDirectory)
        let previousKey = try secretStore.read(QuillSecretKeys.trustedRouterAPIKey)
        var nextConfig = appConfig
        nextConfig.authMode = authMode
        nextConfig.developerOverrideEnabled = authMode == .developerOverride
        nextConfig.trustedRouterAccount = profile

        do {
            if let apiKey {
                let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw AppServerRPCError.invalidParams("apiKey must be a non-empty string")
                }
                try secretStore.write(normalized, for: QuillSecretKeys.trustedRouterAPIKey)
            } else {
                try secretStore.delete(QuillSecretKeys.trustedRouterAPIKey)
            }
            try ConfigStore(fileURL: paths.configFile).save(nextConfig)
            appConfig = nextConfig
        } catch {
            do {
                if let previousKey {
                    try secretStore.write(previousKey, for: QuillSecretKeys.trustedRouterAPIKey)
                } else {
                    try secretStore.delete(QuillSecretKeys.trustedRouterAPIKey)
                }
            } catch {
                throw AppServerRPCError.internalError(
                    "Account update failed and the previous credential could not be restored"
                )
            }
            if let rpcError = error as? AppServerRPCError { throw rpcError }
            throw AppServerRPCError.internalError(
                "Could not persist TrustedRouter account: \(error.localizedDescription)"
            )
        }
    }

    private func successNotifications(loginID: String?) -> [AppServerAccountNotification] {
        [
            loginCompletedNotification(loginID: loginID, success: true, error: nil),
            accountUpdatedNotification()
        ]
    }

    private func loginCompletedNotification(
        loginID: String?,
        success: Bool,
        error: String?
    ) -> AppServerAccountNotification {
        AppServerAccountNotification(
            method: "account/login/completed",
            params: .object([
                "loginId": loginID.map(CLIJSONValue.string) ?? .null,
                "success": .bool(success),
                "error": error.map(CLIJSONValue.string) ?? .null
            ])
        )
    }

    private func accountUpdatedNotification() -> AppServerAccountNotification {
        let authMode = (try? resolvedTrustedRouterAPIKey()) == nil
            ? CLIJSONValue.null
            : .string("apikey")
        return AppServerAccountNotification(
            method: "account/updated",
            params: .object([
                "authMode": authMode,
                "planType": .null
            ])
        )
    }

    private func sendAccountNotifications(_ notifications: [AppServerAccountNotification]) async {
        for notification in notifications {
            await sendNotification(notification.method, params: notification.params)
        }
    }

    private func accountErrorDescription(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}
