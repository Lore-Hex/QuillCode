import Foundation
import QuillCodePersistence
import QuillCodePlatform
import QuillCodeTools

struct AppServerMCPOAuthLogin: Sendable {
    var authorizationURL: URL
    var waitForCompletion: @Sendable () async throws -> Void
    var cancel: @Sendable () -> Void
}

protocol AppServerMCPOAuthLoginStarting: Sendable {
    func start(
        configuration: AppServerMCPServerConfiguration,
        requestedScopes: [String]?,
        timeout: TimeInterval,
        secretStore: any MCPSecretStore
    ) throws -> AppServerMCPOAuthLogin
}

struct DefaultAppServerMCPOAuthLoginStarter: AppServerMCPOAuthLoginStarting {
    private let httpClient: any MCPHTTPClient

    init(httpClient: any MCPHTTPClient = URLSessionMCPHTTPClient()) {
        self.httpClient = httpClient
    }

    func start(
        configuration: AppServerMCPServerConfiguration,
        requestedScopes: [String]?,
        timeout: TimeInterval,
        secretStore: any MCPSecretStore
    ) throws -> AppServerMCPOAuthLogin {
        guard case let .remote(serverURL, headers, _) = configuration.transport else {
            throw AppServerRPCError.invalidRequest(
                "MCP server '\(configuration.name)' does not use an HTTP transport."
            )
        }

        let callbackServer = try LoopbackHTTPCallbackServer(
            callbackPath: Self.callbackPath(serverURL: serverURL)
        )
        do {
            let oauthHTTPClient = MCPHTTPHeaderInjectingClient(
                base: httpClient,
                additionalHeaders: headers
            )
            let flow = MCPOAuthFlow(httpClient: oauthHTTPClient)
            let tokenStore = MCPTokenStore(
                serverID: configuration.oauthServerID,
                secretStore: secretStore
            )
            var oauth = try flow.discover(serverURL: serverURL)
            if let resource = configuration.oauthResource { oauth.resource = resource }
            oauth.scopesSupported = requestedScopes
                ?? (configuration.oauthScopes.isEmpty
                    ? oauth.scopesSupported
                    : configuration.oauthScopes)
            let resolvedOAuth = oauth

            let registration = try flow.registerClientIfNeeded(
                configuration: resolvedOAuth,
                redirectURI: callbackServer.callbackURL.absoluteString,
                existing: tokenStore.loadClientRegistration(),
                staticClientID: configuration.oauthClientID
            )
            try tokenStore.saveClientRegistration(registration)
            let authorization = try flow.makeAuthorization(
                configuration: resolvedOAuth,
                clientID: registration.clientID,
                redirectURI: callbackServer.callbackURL.absoluteString,
                scopes: oauth.scopesSupported
            )

            return AppServerMCPOAuthLogin(
                authorizationURL: authorization.authorizationURL,
                waitForCompletion: {
                    defer { callbackServer.cancel() }
                    let callback = try await Self.waitForCallback(
                        callbackServer,
                        timeout: timeout
                    )
                    let code = try flow.parseCallback(
                        callback,
                        expectedState: authorization.state
                    )
                    let tokens = try flow.exchangeCode(
                        configuration: resolvedOAuth,
                        clientID: registration.clientID,
                        redirectURI: callbackServer.callbackURL.absoluteString,
                        code: code,
                        codeVerifier: authorization.codeVerifier
                    )
                    try tokenStore.saveTokens(tokens)
                },
                cancel: { callbackServer.cancel() }
            )
        } catch {
            callbackServer.cancel()
            throw error
        }
    }

    static func callbackPath(serverURL: URL) -> String {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let stableURL = components?.url?.absoluteString ?? serverURL.absoluteString
        let digest = MCPCrypto.sha256(Array(stableURL.utf8)).prefix(9)
        return "/oauth/callback/\(MCPCrypto.base64URLEncoded(Data(digest)))"
    }

    private static func waitForCallback(
        _ callbackServer: LoopbackHTTPCallbackServer,
        timeout: TimeInterval
    ) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await callbackServer.waitForCallback() }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AppServerMCPOAuthError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw AppServerMCPOAuthError.cancelled
            }
            return result
        }
    }
}

struct AppServerMCPSecretStore: MCPSecretStore {
    private let store: FileSecretStore

    init(directory: URL) {
        self.store = FileSecretStore(directory: directory)
    }

    func read(_ key: String) throws -> String? { try store.read(key) }
    func write(_ value: String, for key: String) throws { try store.write(value, for: key) }
    func delete(_ key: String) throws { try store.delete(key) }
}

struct AppServerPendingMCPOAuthLogin: Sendable {
    var id: UUID
    var name: String
    var threadID: String?
    var operation: AppServerMCPOAuthLogin
    var task: Task<Void, Never>?
}

struct AppServerMCPOAuthRPCOutcome: Sendable {
    var result: CLIJSONValue
    var loginID: UUID
}

private enum AppServerMCPOAuthError: Error, LocalizedError {
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timedOut: "MCP OAuth login timed out."
        case .cancelled: "MCP OAuth login was cancelled."
        }
    }
}

extension AppServerSession {
    func startMCPServerOAuthLogin(_ raw: CLIJSONValue) async throws -> AppServerMCPOAuthRPCOutcome {
        let params = try AppServerParams(raw)
        let name = try params.requiredString("name")
        let threadID = try params.optionalString("threadId")
        let requestedScopes = try params.optionalArray("scopes").map { values in
            try values.map { value in
                guard let scope = value.stringValue,
                      !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      scope.count <= 512 else {
                    throw AppServerRPCError.invalidParams(
                        "scopes must contain non-empty strings no longer than 512 characters"
                    )
                }
                return scope
            }
        }
        let timeout = TimeInterval(max(1, try params.optionalInt("timeoutSecs") ?? 300))
        let context = try await mcpContext(threadID: threadID)
        guard let configuration = context.configurations[name] else {
            throw AppServerRPCError.invalidRequest("No MCP server named '\(name)' found.")
        }
        guard case .remote = configuration.transport else {
            throw AppServerRPCError.invalidRequest(
                "MCP server '\(name)' does not use an HTTP transport."
            )
        }
        guard configuration.authStatus != .bearerToken else {
            throw AppServerRPCError.invalidRequest(
                "MCP server '\(name)' already uses configured bearer authorization."
            )
        }
        guard !pendingMCPOAuthLogins.values.contains(where: {
            $0.name == name && $0.threadID == threadID
        }) else {
            throw AppServerRPCError.invalidRequest(
                "MCP OAuth login is already in progress for '\(name)'."
            )
        }

        let operation: AppServerMCPOAuthLogin
        do {
            operation = try mcpOAuthLoginStarter.start(
                configuration: configuration,
                requestedScopes: requestedScopes,
                timeout: timeout,
                secretStore: mcpSecretStore
            )
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw AppServerRPCError.internalError(
                "Could not start MCP OAuth login: \(mcpOAuthErrorDescription(error))"
            )
        }

        let loginID = UUID()
        pendingMCPOAuthLogins[loginID] = AppServerPendingMCPOAuthLogin(
            id: loginID,
            name: name,
            threadID: threadID,
            operation: operation,
            task: nil
        )
        return AppServerMCPOAuthRPCOutcome(
            result: .object([
                "authorizationUrl": .string(operation.authorizationURL.absoluteString)
            ]),
            loginID: loginID
        )
    }

    func launchMCPServerOAuthLogin(_ loginID: UUID) {
        guard var pending = pendingMCPOAuthLogins[loginID], pending.task == nil else { return }
        let operation = pending.operation
        pending.task = Task { [self] in
            do {
                try await operation.waitForCompletion()
                await completeMCPServerOAuthLogin(loginID, error: nil)
            } catch {
                await completeMCPServerOAuthLogin(loginID, error: error)
            }
        }
        pendingMCPOAuthLogins[loginID] = pending
    }

    func cancelAllMCPServerOAuthLogins() {
        let pending = pendingMCPOAuthLogins.values
        pendingMCPOAuthLogins.removeAll(keepingCapacity: false)
        for login in pending {
            login.operation.cancel()
            login.task?.cancel()
        }
    }

    private func completeMCPServerOAuthLogin(_ loginID: UUID, error: Error?) async {
        guard let pending = pendingMCPOAuthLogins.removeValue(forKey: loginID),
              !inputFinished else { return }
        let success = error == nil
        if success { await mcpRegistry.reload() }
        await sendNotification(
            "mcpServer/oauthLogin/completed",
            params: .object([
                "name": .string(pending.name),
                "threadId": pending.threadID.map(CLIJSONValue.string) ?? .null,
                "success": .bool(success),
                "error": error.map { .string(mcpOAuthErrorDescription($0)) } ?? .null
            ])
        )
    }

    private func mcpOAuthErrorDescription(_ error: Error) -> String {
        switch error {
        case MCPOAuthError.registrationFailed(let statusCode, _):
            return "MCP dynamic client registration failed with HTTP \(statusCode)."
        case MCPOAuthError.tokenExchangeFailed(let statusCode, _):
            return "MCP OAuth token exchange failed with HTTP \(statusCode)."
        case let localized as LocalizedError:
            return localized.errorDescription ?? String(describing: error)
        default:
            return String(describing: error)
        }
    }
}
