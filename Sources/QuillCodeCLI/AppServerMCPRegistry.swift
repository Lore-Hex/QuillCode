import Foundation
import QuillCodeTools

struct AppServerMCPServerStatus: Sendable, Hashable {
    var configuration: AppServerMCPServerConfiguration
    var probe: MCPServerProbeResult?
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
    private var entries: [Key: Entry] = [:]

    init(launcher: any MCPClientLaunching = DefaultMCPClientLauncher()) {
        self.launcher = launcher
    }

    func statuses(
        scope: String,
        configurations: [String: AppServerMCPServerConfiguration],
        detail: MCPProbeDetail
    ) -> [AppServerMCPServerStatus] {
        removeStaleEntries(scope: scope, configurations: configurations)
        return configurations.keys.sorted().compactMap { name in
            guard let configuration = configurations[name] else { return nil }
            do {
                let entry = try probedEntry(scope: scope, configuration: configuration, detail: detail)
                return AppServerMCPServerStatus(configuration: configuration, probe: entry.probe)
            } catch {
                remove(scope: scope, server: name)
                return AppServerMCPServerStatus(configuration: configuration, probe: nil)
            }
        }
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
        let launched = try launcher.launch(request: configuration.launchRequest()) { _ in }
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
}
