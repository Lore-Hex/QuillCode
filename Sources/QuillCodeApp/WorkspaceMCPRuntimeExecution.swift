import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

extension WorkspaceMCPRuntime {
    static func streamingExecutionOverride(
        sessions: [String: any WorkspaceMCPSession],
        summaries: [String: MCPServerProbeSummary]
    ) -> AgentStreamingToolExecutionOverride? {
        guard !sessions.isEmpty else { return nil }

        return { call, _ in
            guard call.name == ToolDefinition.mcpCall.name else { return nil }
            return Self.executeToolCallStream(
                call,
                sessions: sessions,
                permissions: WorkspaceMCPAdvertisedCapabilities(summaries: summaries)
            )
        }
    }

    static func executionOverride(
        sessions: [String: any WorkspaceMCPSession],
        summaries: [String: MCPServerProbeSummary]
    ) -> AgentToolExecutionOverride? {
        guard !sessions.isEmpty else { return nil }

        return { call, _ in
            Self.execute(call: call, sessions: sessions, summaries: summaries)
        }
    }

    static func execute(
        call: ToolCall,
        sessions: [String: any WorkspaceMCPSession],
        summaries: [String: MCPServerProbeSummary]
    ) -> ToolResult? {
        let permissions = WorkspaceMCPAdvertisedCapabilities(summaries: summaries)

        do {
            switch call.name {
            case ToolDefinition.mcpCall.name:
                return try executeToolCall(call, sessions: sessions, permissions: permissions)

            case ToolDefinition.mcpReadResource.name:
                return try executeResourceRead(call, sessions: sessions, summaries: summaries)

            case ToolDefinition.mcpGetPrompt.name:
                return try executePromptGet(call, sessions: sessions, permissions: permissions)

            default:
                return nil
            }
        } catch {
            return ToolResult(ok: false, error: userFacingError(error))
        }
    }

    private static func executeToolCall(
        _ call: ToolCall,
        sessions: [String: any WorkspaceMCPSession],
        permissions: WorkspaceMCPAdvertisedCapabilities
    ) throws -> ToolResult {
        let request = try MCPToolCallRequest(argumentsJSON: call.argumentsJSON)
        guard let session = sessions[request.serverID] else {
            return missingRunningServerResult(request.serverID)
        }
        guard permissions.server(request.serverID, advertisesTool: request.toolName) else {
            return ToolResult(
                ok: false,
                error: "MCP tool \(request.toolName) was not advertised by \(request.serverID)."
            )
        }
        return try session.callTool(
            toolName: request.toolName,
            argumentsJSON: request.toolArgumentsJSON,
            timeout: 10.0
        )
    }

    private static func executeToolCallStream(
        _ call: ToolCall,
        sessions: [String: any WorkspaceMCPSession],
        permissions: WorkspaceMCPAdvertisedCapabilities
    ) -> AsyncThrowingStream<AgentStreamingToolExecutionEvent, Error> {
        do {
            let request = try MCPToolCallRequest(argumentsJSON: call.argumentsJSON)
            guard let session = sessions[request.serverID] else {
                return singleResultStream(missingRunningServerResult(request.serverID))
            }
            guard permissions.server(request.serverID, advertisesTool: request.toolName) else {
                return singleResultStream(ToolResult(
                    ok: false,
                    error: "MCP tool \(request.toolName) was not advertised by \(request.serverID)."
                ))
            }
            let arguments = try MCPJSONValue(jsonData: Data(request.toolArgumentsJSON.utf8))
            guard arguments.objectValue != nil else {
                return singleResultStream(ToolResult(
                    ok: false,
                    error: "MCP tool arguments must be a JSON object."
                ))
            }
            let events = session.callToolEvents(
                toolName: request.toolName,
                arguments: arguments,
                metadata: nil,
                timeout: 30.0
            )
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await event in events {
                            switch event {
                            case .progress(let progress):
                                continuation.yield(.progress(progress))
                            case .result(let result):
                                continuation.yield(.result(result.agentToolResult()))
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            return singleResultStream(ToolResult(ok: false, error: userFacingError(error)))
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

    private static func executeResourceRead(
        _ call: ToolCall,
        sessions: [String: any WorkspaceMCPSession],
        summaries: [String: MCPServerProbeSummary]
    ) throws -> ToolResult {
        let request = try MCPResourceReadRequest(argumentsJSON: call.argumentsJSON)
        guard let session = sessions[request.serverID] else {
            return missingRunningServerResult(request.serverID)
        }
        guard let uri = request.resourceURI(in: summaries[request.serverID]) else {
            return ToolResult(
                ok: false,
                error: "MCP resource \(request.resourceIdentifier) was not advertised by \(request.serverID)."
            )
        }
        return try session.readResource(uri: uri, timeout: 10.0)
    }

    private static func executePromptGet(
        _ call: ToolCall,
        sessions: [String: any WorkspaceMCPSession],
        permissions: WorkspaceMCPAdvertisedCapabilities
    ) throws -> ToolResult {
        let request = try MCPPromptGetRequest(argumentsJSON: call.argumentsJSON)
        guard let session = sessions[request.serverID] else {
            return missingRunningServerResult(request.serverID)
        }
        guard permissions.server(request.serverID, advertisesPrompt: request.promptName) else {
            return ToolResult(
                ok: false,
                error: "MCP prompt \(request.promptName) was not advertised by \(request.serverID)."
            )
        }
        return try session.getPrompt(
            name: request.promptName,
            argumentsJSON: request.promptArgumentsJSON,
            timeout: 10.0
        )
    }

    private static func missingRunningServerResult(_ serverID: String) -> ToolResult {
        ToolResult(ok: false, error: "MCP server is not running or is not Ready: \(serverID)")
    }

    private static func userFacingError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }
}

private struct WorkspaceMCPAdvertisedCapabilities: Sendable {
    private let toolNamesByServer: [String: Set<String>]
    private let promptNamesByServer: [String: Set<String>]

    init(summaries: [String: MCPServerProbeSummary]) {
        self.toolNamesByServer = summaries.mapValues { Set($0.toolNames) }
        self.promptNamesByServer = summaries.mapValues { Set($0.promptNames) }
    }

    func server(_ id: String, advertisesTool toolName: String) -> Bool {
        toolNamesByServer[id]?.contains(toolName) == true
    }

    func server(_ id: String, advertisesPrompt promptName: String) -> Bool {
        promptNamesByServer[id]?.contains(promptName) == true
    }
}
