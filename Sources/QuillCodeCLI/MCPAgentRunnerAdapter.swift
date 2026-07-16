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
    private let elicitationHandler: (@Sendable (
        String,
        MCPClientElicitationRequest
    ) async -> MCPClientElicitationResponse)?

    static func prepare(
        registry: AppServerMCPRegistry,
        scope: String,
        configurations: [String: AppServerMCPServerConfiguration],
        elicitationHandler: (@Sendable (
            String,
            MCPClientElicitationRequest
        ) async -> MCPClientElicitationResponse)? = nil
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
            catalog: catalog,
            elicitationHandler: elicitationHandler
        )
    }

    func configure(_ runner: AgentRunner) -> AgentRunner {
        var configured = runner
        configured.additionalToolDefinitions.append(contentsOf: catalog.definitions)
        let inheritedStreamingExecution = configured.streamingToolExecutionOverride
        let catalog = catalog
        let registry = registry
        let scope = scope
        let configurations = configurations
        let elicitationHandler = elicitationHandler
        configured.streamingToolExecutionOverride = { call, workspaceRoot in
            guard let route = catalog.route(forModelName: call.name) else {
                return inheritedStreamingExecution?(call, workspaceRoot)
            }
            guard let server = configurations[route.serverName] else {
                return Self.singleResultStream(ToolResult(
                    ok: false,
                    error: "MCP server '\(route.serverName)' is no longer configured."
                ))
            }
            return Self.agentToolStream(
                registry: registry,
                scope: scope,
                configuration: server,
                route: route,
                argumentsJSON: call.argumentsJSON,
                elicitationHandler: elicitationHandler
            )
        }
        return configured
    }

    private static func agentToolStream(
        registry: AppServerMCPRegistry,
        scope: String,
        configuration: AppServerMCPServerConfiguration,
        route: MCPAgentToolRoute,
        argumentsJSON: String,
        elicitationHandler: (@Sendable (
            String,
            MCPClientElicitationRequest
        ) async -> MCPClientElicitationResponse)?
    ) -> AsyncThrowingStream<AgentStreamingToolExecutionEvent, Error> {
        let scopedElicitationHandler: MCPClientElicitationHandler?
        if let elicitationHandler {
            scopedElicitationHandler = { request in
                await elicitationHandler(route.serverName, request)
            }
        } else {
            scopedElicitationHandler = nil
        }
        return AsyncThrowingStream<AgentStreamingToolExecutionEvent, Error> { continuation in
            let task = Task {
                do {
                    let events = try await registry.agentToolEvents(
                        scope: scope,
                        configuration: configuration,
                        route: route,
                        argumentsJSON: argumentsJSON,
                        elicitationHandler: scopedElicitationHandler
                    )
                    for try await event in events {
                        try Task.checkCancellation()
                        switch event {
                        case .progress(let progress):
                            continuation.yield(.progress(progress))
                        case .result(let result):
                            continuation.yield(.result(result.agentToolResult()))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.yield(.result(ToolResult(
                        ok: false,
                        error: "MCP tool '\(route.serverName)/\(route.toolName)' failed: "
                            + error.localizedDescription
                    )))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func singleResultStream(
        _ result: ToolResult
    ) -> AsyncThrowingStream<AgentStreamingToolExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.result(result))
            continuation.finish()
        }
    }
}
