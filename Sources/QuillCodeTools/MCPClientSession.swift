import Foundation
import QuillCodeCore

/// Shared MCP session surface used by both the desktop workspace and app-server.
public protocol MCPClientSession: Sendable {
    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult
    func probe(detail: MCPProbeDetail, timeout: TimeInterval) throws -> MCPServerProbeResult
    func callTool(toolName: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult
    func callToolResult(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval
    ) throws -> MCPToolCallResult
    func readResource(uri: String, timeout: TimeInterval) throws -> ToolResult
    func readResourceResult(uri: String, timeout: TimeInterval) throws -> MCPResourceReadResult
    func getPrompt(name: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult
}

public extension MCPClientSession {
    func probe(detail: MCPProbeDetail, timeout: TimeInterval) throws -> MCPServerProbeResult {
        try probe(timeout: timeout)
    }

    func callToolResult(
        toolName: String,
        arguments: MCPJSONValue?,
        metadata: MCPJSONValue?,
        timeout: TimeInterval
    ) throws -> MCPToolCallResult {
        _ = metadata
        let argumentsJSON = try Self.encodedJSONObject(arguments ?? .object([:]))
        let result = try callTool(toolName: toolName, argumentsJSON: argumentsJSON, timeout: timeout)
        let text = result.ok ? result.stdout : (result.stderr.isEmpty ? result.error ?? "" : result.stderr)
        return MCPToolCallResult(
            content: text.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(text)])],
            isError: !result.ok
        )
    }

    func readResourceResult(uri: String, timeout: TimeInterval) throws -> MCPResourceReadResult {
        let result = try readResource(uri: uri, timeout: timeout)
        let text = result.ok ? result.stdout : (result.stderr.isEmpty ? result.error ?? "" : result.stderr)
        guard result.ok else {
            throw MCPProbeError.responseError(text.isEmpty ? "MCP resource read failed." : text)
        }
        return MCPResourceReadResult(
            contents: text.isEmpty ? [] : [.object(["uri": .string(uri), "text": .string(text)])]
        )
    }

    private static func encodedJSONObject(_ value: MCPJSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard data.count <= MCPJSONValue.maximumEncodedBytes else {
            throw MCPProbeError.invalidMessage("MCP JSON exceeded the transport size limit.")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension MCPStdioProber: MCPClientSession {}
extension MCPHTTPProber: MCPClientSession {}
