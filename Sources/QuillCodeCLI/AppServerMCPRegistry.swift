import Foundation
import QuillCodeCore
import QuillCodeTools

struct AppServerMCPServerStatus: Sendable, Hashable {
    var configuration: AppServerMCPServerConfiguration
    var probe: MCPServerProbeResult?
}

struct AppServerMCPRequiredServersError: LocalizedError, Sendable {
    var failures: [String]

    var errorDescription: String? {
        "required MCP servers failed to initialize: \(failures.joined(separator: "; "))"
    }
}

actor AppServerMCPRegistry {
    private struct Key: Sendable, Hashable {
        var scope: String
        var server: String
    }

    private struct Entry: Sendable {
        var configuration: AppServerMCPServerConfiguration
        var launched: MCPLaunchedClient
        var probe: MCPServerProbeResult?
        var detail: MCPProbeDetail?
    }

    private let launcher: any MCPClientLaunching
    private let secretStore: (any MCPSecretStore)?
    private let httpClient: any MCPHTTPClient
    private var entries: [Key: Entry] = [:]

    init(
        launcher: any MCPClientLaunching = DefaultMCPClientLauncher(),
        secretStore: (any MCPSecretStore)? = nil,
        httpClient: any MCPHTTPClient = URLSessionMCPHTTPClient()
    ) {
        self.launcher = launcher
        self.secretStore = secretStore
        self.httpClient = httpClient
    }

    func statuses(
        scope: String,
        configurations: [String: AppServerMCPServerConfiguration],
        detail: MCPProbeDetail
    ) -> [AppServerMCPServerStatus] {
        removeStaleEntries(scope: scope, configurations: configurations)
        return configurations.keys.sorted().compactMap { name in
            guard let configuration = configurations[name] else { return nil }
            let reportedConfiguration = configuration.reportingStoredOAuth(
                secretStore: secretStore
            )
            do {
                let entry = try probedEntry(scope: scope, configuration: configuration, detail: detail)
                return AppServerMCPServerStatus(
                    configuration: reportedConfiguration,
                    probe: entry.probe
                )
            } catch {
                remove(scope: scope, server: name)
                return AppServerMCPServerStatus(
                    configuration: reportedConfiguration,
                    probe: nil
                )
            }
        }
    }

    func agentToolCatalog(
        scope: String,
        configurations: [String: AppServerMCPServerConfiguration]
    ) throws -> MCPAgentToolCatalog {
        removeStaleEntries(scope: scope, configurations: configurations)
        var servers: [MCPAgentServerTools] = []
        var requiredFailures: [String] = []

        for configuration in configurations.values.sorted(by: { $0.name < $1.name }) {
            do {
                let entry = try probedEntry(
                    scope: scope,
                    configuration: configuration,
                    detail: .toolsAndAuthOnly
                )
                let tools = Self.agentTools(from: entry.probe).filter { value in
                    guard let name = value.objectValue?["name"]?.stringValue else { return false }
                    return configuration.permitsTool(named: name)
                }
                servers.append(MCPAgentServerTools(serverName: configuration.name, tools: tools))
            } catch {
                remove(scope: scope, server: configuration.name)
                if configuration.required {
                    requiredFailures.append("\(configuration.name): \(error.localizedDescription)")
                }
            }
        }

        guard requiredFailures.isEmpty else {
            throw AppServerMCPRequiredServersError(failures: requiredFailures)
        }
        return MCPAgentToolCatalog(servers: servers)
    }

    func isServerReady(
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        detail: MCPProbeDetail
    ) -> Bool {
        let key = Key(scope: scope, server: configuration.name)
        guard let entry = entries[key],
              entry.configuration == configuration,
              entry.launched.process.isRunning,
              entry.probe != nil
        else {
            return false
        }
        return entry.detail == detail || entry.detail == .full
    }

    func prepareServer(
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        detail: MCPProbeDetail
    ) throws {
        do {
            _ = try probedEntry(scope: scope, configuration: configuration, detail: detail)
        } catch {
            remove(scope: scope, server: configuration.name)
            throw error
        }
    }

    func agentToolEvents(
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        route: MCPAgentToolRoute,
        argumentsJSON: String
    ) throws -> AsyncThrowingStream<MCPClientToolEvent, Error> {
        guard route.serverName == configuration.name,
              configuration.permitsTool(named: route.toolName)
        else {
            throw MCPProbeError.responseError(
                "MCP tool '\(route.serverName)/\(route.toolName)' is not enabled."
            )
        }
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = try MCPJSONValue(jsonData: Data((trimmed.isEmpty ? "{}" : trimmed).utf8))
        guard arguments.objectValue != nil else {
            throw MCPProbeError.invalidMessage("MCP tool arguments must be a JSON object.")
        }
        let entry = try probedEntry(
            scope: scope,
            configuration: configuration,
            detail: .toolsAndAuthOnly
        )
        return entry.launched.session.callToolEvents(
            toolName: route.toolName,
            arguments: arguments,
            metadata: nil,
            timeout: configuration.toolTimeout
        )
    }

    func callTool(
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        tool: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?
    ) throws -> MCPToolCallResult {
        guard configuration.permitsTool(named: tool) else {
            throw MCPProbeError.responseError("MCP tool '\(tool)' is disabled for server '\(configuration.name)'.")
        }
        let entry = try probedEntry(scope: scope, configuration: configuration, detail: .toolsAndAuthOnly)
        return try entry.launched.session.callToolResult(
            toolName: tool,
            arguments: arguments,
            metadata: metadata,
            timeout: configuration.toolTimeout
        )
    }

    func readResource(
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        uri: String
    ) throws -> MCPResourceReadResult {
        let entry = try probedEntry(scope: scope, configuration: configuration, detail: .toolsAndAuthOnly)
        return try entry.launched.session.readResourceResult(uri: uri, timeout: configuration.toolTimeout)
    }

    func reload() {
        terminateAll()
    }

    func terminateAll() {
        for entry in entries.values {
            entry.launched.process.clearReadabilityHandlers()
            if entry.launched.process.isRunning { entry.launched.process.terminate() }
        }
        entries.removeAll()
    }

    private func probedEntry(
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        detail: MCPProbeDetail
    ) throws -> Entry {
        let key = Key(scope: scope, server: configuration.name)
        var entry = try liveEntry(key: key, configuration: configuration)
        if entry.probe != nil, entry.detail == detail || entry.detail == .full {
            return entry
        }
        if entry.probe != nil, entry.detail == .toolsAndAuthOnly, detail == .full {
            remove(key: key)
            entry = try liveEntry(key: key, configuration: configuration)
        }
        entry.probe = try entry.launched.session.probe(
            detail: detail,
            timeout: configuration.startupTimeout
        )
        entry.detail = detail
        entry.launched.process.startDrainingStandardError()
        entries[key] = entry
        return entry
    }

    private func liveEntry(
        key: Key,
        configuration: AppServerMCPServerConfiguration
    ) throws -> Entry {
        if let entry = entries[key],
           entry.configuration == configuration,
           entry.launched.process.isRunning {
            return entry
        }
        remove(key: key)
        let launched = try launcher.launch(
            request: configuration.launchRequest(
                secretStore: secretStore,
                httpClient: httpClient
            )
        ) { _ in }
        let entry = Entry(configuration: configuration, launched: launched)
        entries[key] = entry
        return entry
    }

    private func removeStaleEntries(
        scope: String,
        configurations: [String: AppServerMCPServerConfiguration]
    ) {
        let stale = entries.keys.filter { key in
            guard key.scope == scope else { return false }
            return configurations[key.server] != entries[key]?.configuration
        }
        for key in stale { remove(key: key) }
    }

    private func remove(scope: String, server: String) {
        remove(key: Key(scope: scope, server: server))
    }

    private func remove(key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        entry.launched.process.clearReadabilityHandlers()
        if entry.launched.process.isRunning { entry.launched.process.terminate() }
    }

    private static func agentTools(from probe: MCPServerProbeResult?) -> [MCPJSONValue] {
        guard let probe else { return [] }
        if !probe.tools.isEmpty { return probe.tools }
        return probe.toolDescriptors.map { descriptor in
            .object([
                "name": .string(descriptor.name),
                "description": .string(descriptor.description),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ])
        }
    }
}
