import Foundation

typealias AppServerExecServerClientFactory = @Sendable (
    _ websocketURL: String,
    _ connectTimeout: TimeInterval
) -> any AppServerExecServerClient

actor AppServerEnvironmentRegistry {
    struct ConnectionEvent: Sendable, Equatable {
        var threadID: UUID
        var environmentID: String
        var connected: Bool
    }

    typealias ConnectionEventHandler = @Sendable (ConnectionEvent) async -> Void

    private struct Subscription: Sendable {
        var threadID: UUID
        var environmentID: String
        var startedAt: ContinuousClock.Instant
        var handler: ConnectionEventHandler
    }

    private struct RemoteEntry: Sendable {
        var registrationID: UUID
        var client: any AppServerExecServerClient
        var eventTask: Task<Void, Never>
    }

    private enum Entry: Sendable {
        case local(AppServerEnvironmentInfo)
        case remote(RemoteEntry)
    }

    private static let defaultConnectTimeout: TimeInterval = 10

    private var entries: [String: Entry]
    private var subscriptions: [UUID: Subscription] = [:]
    private let clientFactory: AppServerExecServerClientFactory

    init(
        localCWD: URL,
        environment: [String: String],
        clientFactory: @escaping AppServerExecServerClientFactory = {
            AppServerExecServerWebSocketClient(
                websocketURL: $0,
                connectTimeout: $1
            )
        }
    ) {
        let shellPath = Self.localShellPath(environment: environment)
        let local = AppServerEnvironmentInfo(
            shell: .init(
                name: URL(fileURLWithPath: shellPath).lastPathComponent,
                path: shellPath
            ),
            cwd: localCWD.standardizedFileURL.absoluteString
        )
        self.entries = ["local": .local(local)]
        self.clientFactory = clientFactory
    }

    func add(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try Self.registrationParams(raw)
        let client = clientFactory(params.execServerURL, params.connectTimeout)
        let registrationID = UUID()
        let events = await client.connectionEvents()
        let eventTask = Task { [weak self] in
            for await observation in events {
                guard !Task.isCancelled else { return }
                await self?.publishConnectionEvent(
                    environmentID: params.environmentID,
                    registrationID: registrationID,
                    observation: observation
                )
            }
        }
        let entry = RemoteEntry(
            registrationID: registrationID,
            client: client,
            eventTask: eventTask
        )
        let previous = entries.updateValue(.remote(entry), forKey: params.environmentID)
        if case .remote(let previousRemote) = previous {
            previousRemote.eventTask.cancel()
            Task { await previousRemote.client.close() }
        }
        Task {
            // Registration acknowledges immediately while initial connection proceeds in the
            // background. Later requests may recover a disconnected transport, but status never does.
            try? await client.connect()
        }
        return .object([:])
    }

    func status(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let environmentID = try Self.environmentID(from: raw)
        guard let entry = entries[environmentID] else {
            return AppServerEnvironmentConnectionSnapshot(
                status: .unknown,
                error: "unknown environment id `\(environmentID)`"
            ).rpcValue
        }
        switch entry {
        case .local:
            return AppServerEnvironmentConnectionSnapshot.ready.rpcValue
        case .remote(let remote):
            let snapshot = await remote.client.connectionSnapshot()
            guard case .remote(let current) = entries[environmentID],
                  current.registrationID == remote.registrationID else {
                return AppServerEnvironmentConnectionSnapshot.pending.rpcValue
            }
            return snapshot.rpcValue
        }
    }

    func info(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let environmentID = try Self.environmentID(from: raw)
        do {
            return try await resolve(environmentID).info.rpcValue
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            let detail = (error as? any LocalizedError)?.errorDescription
                ?? String(describing: error)
            throw AppServerRPCError.internalError(
                "failed to get info for environment `\(environmentID)`: \(detail)"
            )
        }
    }

    func resolve(_ environmentID: String) async throws -> AppServerResolvedEnvironment {
        guard let entry = entries[environmentID] else {
            throw AppServerRPCError.invalidRequest(
                "unknown environment id `\(environmentID)`"
            )
        }
        switch entry {
        case .local(let info):
            return .local(info: info)
        case .remote(let remote):
            let info = try await remote.client.environmentInfo()
            guard case .remote(let current) = entries[environmentID],
                  current.registrationID == remote.registrationID else {
                throw AppServerRPCError.invalidRequest(
                    "environment `\(environmentID)` was replaced while connecting; retry the request"
                )
            }
            return .remote(info: info, client: remote.client)
        }
    }

    func subscribe(
        token: UUID,
        threadID: UUID,
        environmentID: String,
        handler: @escaping ConnectionEventHandler
    ) throws {
        guard entries[environmentID] != nil else {
            throw AppServerRPCError.invalidRequest(
                "unknown turn environment id `\(environmentID)`"
            )
        }
        subscriptions[token] = Subscription(
            threadID: threadID,
            environmentID: environmentID,
            startedAt: ContinuousClock.now,
            handler: handler
        )
    }

    func unsubscribe(_ token: UUID) {
        subscriptions[token] = nil
    }

    func validate(_ selections: [AppServerThreadEnvironmentSelection]) throws {
        for selection in selections where entries[selection.environmentID] == nil {
            throw AppServerRPCError.invalidRequest(
                "unknown turn environment id `\(selection.environmentID)`"
            )
        }
    }

    func closeAll() async {
        let remotes = entries.values.compactMap { entry -> RemoteEntry? in
            guard case .remote(let remote) = entry else { return nil }
            return remote
        }
        subscriptions.removeAll()
        for remote in remotes {
            remote.eventTask.cancel()
            await remote.client.close()
        }
    }

    private func publishConnectionEvent(
        environmentID: String,
        registrationID: UUID,
        observation: AppServerExecServerConnectionObservation
    ) async {
        guard case .remote(let current) = entries[environmentID],
              current.registrationID == registrationID else {
            return
        }
        let matchingSubscriptions = subscriptions.values.filter { subscription in
            subscription.environmentID == environmentID
                && observation.observedAt > subscription.startedAt
        }
        for subscription in matchingSubscriptions {
            guard case .remote(let latest) = entries[environmentID],
                  latest.registrationID == registrationID else {
                return
            }
            await subscription.handler(ConnectionEvent(
                threadID: subscription.threadID,
                environmentID: environmentID,
                connected: observation.state == .connected
            ))
        }
    }

    private struct RegistrationParams: Sendable {
        var environmentID: String
        var execServerURL: String
        var connectTimeout: TimeInterval
    }

    private static func registrationParams(_ raw: CLIJSONValue) throws -> RegistrationParams {
        guard let object = raw.objectValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: expected an object")
        }
        let environmentID = try requiredString("environmentId", in: object)
        guard !environmentID.isEmpty else {
            throw AppServerRPCError.invalidRequest(
                "exec-server protocol error: environment id cannot be empty"
            )
        }
        let execServerURL = try requiredString("execServerUrl", in: object)
        let normalizedURL = try normalizedExecServerURL(execServerURL)
        let timeout = try connectTimeout(in: object)
        return RegistrationParams(
            environmentID: environmentID,
            execServerURL: normalizedURL,
            connectTimeout: timeout
        )
    }

    private static func normalizedExecServerURL(_ raw: String) throws -> String {
        let normalizedURL = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedURL.isEmpty else {
            throw AppServerRPCError.invalidRequest(
                "exec-server protocol error: remote environment requires an exec-server url"
            )
        }
        guard normalizedURL.lowercased() != "none" else {
            throw AppServerRPCError.invalidRequest(
                "exec-server protocol error: remote environment cannot use disabled exec-server url"
            )
        }
        guard let url = URL(string: normalizedURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "ws" || scheme == "wss"),
              url.host != nil else {
            throw AppServerRPCError.invalidRequest(
                "exec-server protocol error: unsupported WebSocket URL `\(normalizedURL)`"
            )
        }
        return normalizedURL
    }

    private static func environmentID(from raw: CLIJSONValue) throws -> String {
        guard let object = raw.objectValue else {
            throw AppServerRPCError.invalidRequest("Invalid request: expected an object")
        }
        return try requiredString("environmentId", in: object)
    }

    private static func requiredString(
        _ key: String,
        in object: [String: CLIJSONValue]
    ) throws -> String {
        guard let value = object[key] else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `\(key)`")
        }
        guard let string = value.stringValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: `\(key)` must be a string"
            )
        }
        return string
    }

    private static func connectTimeout(
        in object: [String: CLIJSONValue]
    ) throws -> TimeInterval {
        guard let raw = object["connectTimeoutMs"], raw != .null else {
            return defaultConnectTimeout
        }
        guard let number = raw.numberValue,
              number.isFinite,
              number.rounded() == number,
              number >= 0,
              number < Double(UInt64.max) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: `connectTimeoutMs` must be an unsigned integer"
            )
        }
        return number / 1_000
    }

    private static func localShellPath(environment: [String: String]) -> String {
        guard let configured = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !configured.isEmpty else {
            return "/bin/sh"
        }
        return configured
    }
}
