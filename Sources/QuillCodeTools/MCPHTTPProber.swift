import Foundation
import QuillCodeCore

/// Remote MCP transport: the modern **StreamableHTTP** transport with **failover to the older
/// HTTP+SSE** transport, sharing the exact JSON-RPC framing/models and result mapping used by
/// the stdio `MCPStdioProber`.
///
/// StreamableHTTP: every client→server message is an HTTP POST of a single JSON-RPC object to
/// the endpoint. The server replies with either `application/json` (one response) or
/// `text/event-stream` (an SSE stream carrying the response and any interleaved
/// notifications/requests). A `Mcp-Session-Id` response header, if present, is echoed on every
/// subsequent request.
///
/// HTTP+SSE (the 2024-11-05 transport) failover: when the initial POST is rejected in a way that
/// signals StreamableHTTP is unsupported (405/404/406, or an HTML/redirect response), the prober
/// falls back to opening a `GET` SSE stream to discover the server's message-POST endpoint (the
/// `endpoint` event), then POSTs each request there and reads the reply off the shared SSE
/// stream.
///
/// Everything the server sends is untrusted: JSON bodies go through the bounded
/// `MCPStdioMessageCodec`/`JSONSerialization` path, SSE frames through the bounded
/// `MCPSSEParser`, and every wait is deadline-bounded so a silent server times out rather than
/// hanging the agent. No force-unwraps; tokens are never logged.
public final class MCPHTTPProber: @unchecked Sendable {
    public enum Mode: Sendable, Equatable {
        /// Prefer StreamableHTTP, fall back to HTTP+SSE if the server rejects it.
        case automatic
        /// StreamableHTTP only.
        case streamableHTTP
        /// Legacy HTTP+SSE only.
        case httpSSE
    }

    let endpoint: URL
    let httpClient: any MCPHTTPClient
    let authorization: any MCPRemoteAuthorizing
    let extraHeaders: [String: String]
    let mode: Mode
    let protocolVersion = "2025-03-26"

    let ioLock = NSLock()
    var nextRequestID = 1
    var sessionID: String?
    /// Resolved transport after the first probe: once StreamableHTTP works we never re-attempt
    /// failover, and vice versa.
    var resolvedTransport: ResolvedTransport?
    /// For the HTTP+SSE fallback: the message endpoint discovered from the SSE `endpoint` event.
    var sseMessageEndpoint: URL?
    /// The single long-lived server→client SSE stream for the HTTP+SSE fallback, plus the parser
    /// that carries partial frames across reads. All JSON-RPC replies arrive here.
    var sseStream: MCPHTTPStream?
    var sseParser = MCPSSEParser(maxEventBytes: MCPStdioMessageCodec.maxMessageBytes)

    enum ResolvedTransport: Equatable {
        case streamableHTTP
        case httpSSE
    }

    public init(
        endpoint: URL,
        httpClient: any MCPHTTPClient,
        authorization: any MCPRemoteAuthorizing = MCPNoAuthorization(),
        extraHeaders: [String: String] = [:],
        mode: Mode = .automatic
    ) {
        self.endpoint = endpoint
        self.httpClient = httpClient
        self.authorization = authorization
        self.extraHeaders = extraHeaders
        self.mode = mode
    }

    // MARK: - Public session surface (mirrors MCPStdioProber)

    public func probe(timeout: TimeInterval = 20.0) throws -> MCPServerProbeResult {
        ioLock.lock()
        defer { ioLock.unlock() }
        let deadline = Date().addingTimeInterval(max(1, timeout))

        let initializeResult = try initialize(deadline: deadline)
        // Notify the server we're ready (best-effort; a failure here shouldn't fail the probe).
        try? sendNotification(method: "notifications/initialized", params: [:], deadline: deadline)

        let toolsResult = try request(method: "tools/list", params: [:], deadline: deadline)
        let tools = (toolsResult["tools"] as? [[String: Any]]) ?? []
        let toolDescriptors = MCPStdioResultMapper.toolDescriptors(from: tools)

        let capabilities = initializeResult["capabilities"] as? [String: Any]
        let resources = capabilities?["resources"] == nil
            ? []
            : optionalResourceList(deadline: deadline)
        let promptNames = capabilities?["prompts"] == nil
            ? []
            : optionalListNames(method: "prompts/list", resultKey: "prompts", deadline: deadline)

        let serverInfo = initializeResult["serverInfo"] as? [String: Any]
        return MCPServerProbeResult(
            protocolVersion: initializeResult["protocolVersion"] as? String,
            serverName: serverInfo?["name"] as? String,
            serverVersion: serverInfo?["version"] as? String,
            toolDescriptors: toolDescriptors,
            resourceNames: resources.map(\.displayName),
            resourceURIs: resources.map(\.uri),
            promptNames: promptNames
        )
    }

    public func callTool(
        toolName: String,
        argumentsJSON: String = "{}",
        timeout: TimeInterval = 30.0
    ) throws -> ToolResult {
        ioLock.lock()
        defer { ioLock.unlock() }
        let toolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return ToolResult(ok: false, error: "MCP tool name is required.")
        }
        let arguments = try MCPStdioResultMapper.argumentsObject(from: argumentsJSON)
        let result = try request(
            method: "tools/call",
            params: ["name": toolName, "arguments": arguments],
            deadline: Date().addingTimeInterval(max(1, timeout))
        )
        return MCPStdioResultMapper.toolResult(from: result)
    }

    public func readResource(uri: String, timeout: TimeInterval = 30.0) throws -> ToolResult {
        ioLock.lock()
        defer { ioLock.unlock() }
        let uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else {
            return ToolResult(ok: false, error: "MCP resource URI is required.")
        }
        let result = try request(
            method: "resources/read",
            params: ["uri": uri],
            deadline: Date().addingTimeInterval(max(1, timeout))
        )
        return MCPStdioResultMapper.resourceResult(from: result, uri: uri)
    }

    public func getPrompt(
        name: String,
        argumentsJSON: String = "{}",
        timeout: TimeInterval = 30.0
    ) throws -> ToolResult {
        ioLock.lock()
        defer { ioLock.unlock() }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return ToolResult(ok: false, error: "MCP prompt name is required.")
        }
        let arguments = try MCPStdioResultMapper.argumentsObject(from: argumentsJSON)
        let result = try request(
            method: "prompts/get",
            params: ["name": name, "arguments": arguments],
            deadline: Date().addingTimeInterval(max(1, timeout))
        )
        return MCPStdioResultMapper.promptResult(from: result, name: name)
    }

    // MARK: - JSON-RPC over the resolved transport

    private func initialize(deadline: Date) throws -> [String: Any] {
        let params: [String: Any] = [
            "protocolVersion": protocolVersion,
            "capabilities": [:],
            "clientInfo": ["name": "QuillCode", "version": "0.1.0"]
        ]
        return try request(method: "initialize", params: params, deadline: deadline)
    }

    /// Send a JSON-RPC request and return its `result` object, dispatching to whichever transport
    /// is resolved (attempting StreamableHTTP first under `.automatic`).
    private func request(method: String, params: [String: Any], deadline: Date) throws -> [String: Any] {
        let id = nextID()
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let body = try MCPStdioMessageCodec.jsonBody(message)

        switch effectiveTransport() {
        case .streamableHTTP:
            return try streamableRequest(body: body, id: id, method: method, params: params, deadline: deadline)
        case .httpSSE:
            return try httpSSERequest(body: body, id: id, deadline: deadline)
        case nil:
            // Not yet resolved: try StreamableHTTP, fall back on the failover signal.
            do {
                let result = try streamableRequest(
                    body: body, id: id, method: method, params: params, deadline: deadline
                )
                resolvedTransport = .streamableHTTP
                return result
            } catch let error as MCPHTTPProberError where error.isFailoverSignal && mode == .automatic {
                resolvedTransport = .httpSSE
                // Re-frame with a fresh id for the fallback transport.
                let retryID = nextID()
                var retryMessage = message
                retryMessage["id"] = retryID
                let retryBody = try MCPStdioMessageCodec.jsonBody(retryMessage)
                return try httpSSERequest(body: retryBody, id: retryID, deadline: deadline)
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any], deadline: Date) throws {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        let body = try MCPStdioMessageCodec.jsonBody(message)
        switch effectiveTransport() {
        case .httpSSE:
            _ = try? postMessage(
                to: sseMessageEndpoint ?? endpoint,
                body: body,
                expectResponse: false,
                deadline: deadline
            )
        default:
            _ = try? postStreamable(body: body, deadline: deadline, allowAuthRetry: true)
        }
    }

    private func effectiveTransport() -> ResolvedTransport? {
        switch mode {
        case .streamableHTTP: return .streamableHTTP
        case .httpSSE: return .httpSSE
        case .automatic: return resolvedTransport
        }
    }


    // MARK: - Optional list helpers (mirrors MCPStdioProber)

    private func optionalListNames(method: String, resultKey: String, deadline: Date) -> [String] {
        guard let result = try? request(method: method, params: [:], deadline: deadline) else { return [] }
        return MCPStdioResultMapper.names(from: result, resultKey: resultKey, nameKeys: ["name"])
    }

    private func optionalResourceList(deadline: Date) -> [MCPStdioResultMapper.ResourceListEntry] {
        guard let result = try? request(method: "resources/list", params: [:], deadline: deadline) else { return [] }
        return MCPStdioResultMapper.resourceList(from: result)
    }

    // MARK: - Request identifiers

    private func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }
}
