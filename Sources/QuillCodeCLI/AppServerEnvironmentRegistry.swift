import Foundation

typealias AppServerExecServerClientFactory = @Sendable (
    _ websocketURL: String,
    _ connectTimeout: TimeInterval
) -> any AppServerExecServerClient

actor AppServerEnvironmentRegistry {
    private enum Entry: Sendable {
        case local(AppServerEnvironmentInfo)
        case remote(any AppServerExecServerClient)
    }

    private static let defaultConnectTimeout: TimeInterval = 10

    private var entries: [String: Entry]
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
        let previous = entries.updateValue(.remote(client), forKey: params.environmentID)
        if case .remote(let previousClient) = previous {
            Task { await previousClient.close() }
        }
        Task {
            // Registration is intentionally lazy, matching Codex: environment/add acknowledges the
            // registry mutation immediately and environment/info surfaces connection failures.
            try? await client.connect()
        }
        return .object([:])
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
        case .remote(let client):
            return try await .remote(info: client.environmentInfo(), client: client)
        }
    }

    func validate(_ selections: [AppServerThreadEnvironmentSelection]) throws {
        for selection in selections where entries[selection.environmentID] == nil {
            throw AppServerRPCError.invalidRequest(
                "unknown turn environment id `\(selection.environmentID)`"
            )
        }
    }

    func closeAll() async {
        let clients = entries.values.compactMap { entry -> (any AppServerExecServerClient)? in
            guard case .remote(let client) = entry else { return nil }
            return client
        }
        for client in clients { await client.close() }
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
