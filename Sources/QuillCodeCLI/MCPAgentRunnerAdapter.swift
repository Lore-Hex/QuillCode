import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

/// Applies one initialized MCP catalog to an agent while preserving any existing host-tool
/// override. App-server turns and standalone exec runs share this path so schemas and routing stay
/// byte-for-byte consistent across both protocol surfaces.
struct MCPAgentRunnerAdapter: Sendable {
    let routesByModelName: [String: MCPAgentToolRoute]

    private let registry: AppServerMCPRegistry
    private let scope: String
    private let configurations: [String: AppServerMCPServerConfiguration]
    private let catalog: MCPAgentToolCatalog

    static func prepare(
        registry: AppServerMCPRegistry,
        scope: String,
        configurations: [String: AppServerMCPServerConfiguration]
    ) async throws -> Self {
        let catalog = try await registry.agentToolCatalog(
            scope: scope,
            configurations: configurations
        )
        return Self(
            routesByModelName: catalog.routesByModelName,
            registry: registry,
            scope: scope,
            configurations: configurations,
            catalog: catalog
        )
    }

    func configure(_ runner: AgentRunner) -> AgentRunner {
        var configured = runner
        configured.additionalToolDefinitions.append(contentsOf: catalog.definitions)
        let inheritedExecution = configured.toolExecutionOverride
        let catalog = catalog
        let registry = registry
        let scope = scope
        let configurations = configurations
        configured.toolExecutionOverride = { call, workspaceRoot in
            guard let route = catalog.route(forModelName: call.name) else {
                return await inheritedExecution?(call, workspaceRoot)
            }
            guard let server = configurations[route.serverName] else {
                return ToolResult(
                    ok: false,
                    error: "MCP server '\(route.serverName)' is no longer configured."
                )
            }
            return await registry.executeAgentTool(
                scope: scope,
                configuration: server,
                route: route,
                argumentsJSON: call.argumentsJSON
            )
        }
        return configured
    }
}
