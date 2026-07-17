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

    private struct RemoteEntry: Sendable {
        var registrationID: UUID
        var client: any AppServerExecServerClient
    }

    private enum Entry: Sendable {
        case local(AppServerEnvironmentInfo)
        case remote(RemoteEntry)
    }

    private struct Subscription: Sendable {
        var threadID: UUID
        var environmentID: String
        var handler: ConnectionEventHandler
    }

    private static let defaultConnectTimeout: TimeInterval = 10

    private var entries: [String: Entry]
    private var snapshots: [String: AppServerEnvironmentConnectionSnapshot] = [
        "local": .ready
    ]
    private var subscriptions: [UUID: Subscription] = [:]
    private var monitorTasks: [String: Task<Void, Never>] = [:]
    private let clientFactory: AppServerExecServerClientFactory
    private let monitorInterval: Duration

    init(
        localCWD: URL,
        environment: [String: String],
        monitorInterval: Duration = .seconds(1),
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
        self.monitorInterval = monitorInterval
    }

    func add(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try Self.registrationParams(raw)
        let client = clientFactory(params.execServerURL, params.connectTimeout)
        let registrationID = UUID()
        let previous = entries.updateValue(
            .remote(.init(registrationID: registrationID, client: client)),
            forKey: params.environmentID
        )
        snapshots[params.environmentID] = .pending
        restartMonitor(
            environmentID: params.environmentID,
            registrationID: registrationID,
            client: client
        )
        if case .remote(let previousEntry) = previous {
            Task { await previousEntry.client.close() }
        }
        Task {
            // Registration is intentionally lazy, matching Codex: environment/add acknowledges the
            // registry mutation immediately and environment/info surfaces connection failures.
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
                return (snapshots[environmentID] ?? .pending).rpcValue
            }
            await record(
                snapshot,
                environmentID: environmentID,
                registrationID: remote.registrationID
            )
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
        monitorTasks.values.forEach { $0.cancel() }
        monitorTasks.removeAll()
        subscriptions.removeAll()
        let clients = entries.values.compactMap { entry -> (any AppServerExecServerClient)? in
            guard case .remote(let remote) = entry else { return nil }
            return remote.client
        }
        for client in clients { await client.close() }
    }

    private func restartMonitor(
        environmentID: String,
        registrationID: UUID,
        client: any AppServerExecServerClient
    ) {
        monitorTasks[environmentID]?.cancel()
        monitorTasks[environmentID] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snapshot = await client.connectionSnapshot()
                await self.record(
                    snapshot,
                    environmentID: environmentID,
                    registrationID: registrationID
                )
                do {
                    try await Task.sleep(for: self.monitorInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func record(
        _ snapshot: AppServerEnvironmentConnectionSnapshot,
        environmentID: String,
        registrationID: UUID
    ) async {
        guard case .remote(let current) = entries[environmentID],
              current.registrationID == registrationID else {
            return
        }
        let previous = snapshots.updateValue(snapshot, forKey: environmentID)
        guard let previous,
              previous.isConnected != snapshot.isConnected else {
            return
        }
        let eventSubscriptions = subscriptions.values.filter {
            $0.environmentID == environmentID
        }
        let connected = snapshot.isConnected
        for subscription in eventSubscriptions {
            guard case .remote(let current) = entries[environmentID],
                  current.registrationID == registrationID else {
                return
            }
            await subscription.handler(ConnectionEvent(
                threadID: subscription.threadID,
                environmentID: environmentID,
                connected: connected
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
        let normalizedURL = execServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let timeout = try connectTimeout(in: object)
        return RegistrationParams(
            environmentID: environmentID,
            execServerURL: execServerURL,
            connectTimeout: timeout
        )
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
