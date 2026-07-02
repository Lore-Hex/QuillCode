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

    private let endpoint: URL
    private let httpClient: any MCPHTTPClient
    private let authorization: any MCPRemoteAuthorizing
    private let extraHeaders: [String: String]
    private let mode: Mode
    private let protocolVersion = "2025-03-26"

    private let ioLock = NSLock()
    private var nextRequestID = 1
    private var sessionID: String?
    /// Resolved transport after the first probe: once StreamableHTTP works we never re-attempt
    /// failover, and vice versa.
    private var resolvedTransport: ResolvedTransport?
    /// For the HTTP+SSE fallback: the message endpoint discovered from the SSE `endpoint` event.
    private var sseMessageEndpoint: URL?
    /// The single long-lived server→client SSE stream for the HTTP+SSE fallback, plus the parser
    /// that carries partial frames across reads. All JSON-RPC replies arrive here.
    private var sseStream: MCPHTTPStream?
    private var sseParser = MCPSSEParser(maxEventBytes: MCPStdioMessageCodec.maxMessageBytes)

    private enum ResolvedTransport: Equatable {
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
            _ = try? postMessage(to: sseMessageEndpoint ?? endpoint, body: body, expectResponse: false, deadline: deadline)
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

    // MARK: - StreamableHTTP

    private func streamableRequest(
        body: Data,
        id: Int,
        method: String,
        params: [String: Any],
        deadline: Date
    ) throws -> [String: Any] {
        let outcome = try postStreamable(body: body, deadline: deadline, allowAuthRetry: true)
        switch outcome {
        case .json(let object):
            return try Self.extractResult(from: object, matchingID: id)
        case .sse(let stream):
            defer { stream.cancel() }
            // A StreamableHTTP POST returns a fresh, per-request SSE stream, so a fresh parser.
            var parser = MCPSSEParser(maxEventBytes: MCPStdioMessageCodec.maxMessageBytes)
            return try readMatchingResponse(fromSSE: stream, parser: &parser, id: id, deadline: deadline)
        }
    }

    private enum PostOutcome {
        case json([String: Any])
        case sse(MCPHTTPStream)
    }

    /// POST a JSON-RPC body under StreamableHTTP, handling a single 401 auth refresh+retry and
    /// classifying failover signals. Reads the response as JSON or an SSE stream by content type.
    private func postStreamable(body: Data, deadline: Date, allowAuthRetry: Bool) throws -> PostOutcome {
        let request = MCPHTTPRequest(
            url: endpoint,
            method: "POST",
            headers: streamableHeaders(),
            body: body,
            timeout: remaining(until: deadline),
            maxResponseBytes: MCPStdioMessageCodec.maxMessageBytes
        )
        let stream: MCPHTTPStream
        do {
            stream = try httpClient.openStream(request)
        } catch let error as MCPHTTPClientError {
            throw MCPHTTPProberError.transport(error.description)
        }

        // 401 → refresh once, retry once. Never loops.
        if stream.statusCode == 401 {
            stream.cancel()
            if allowAuthRetry, authorization.refreshAuthorizationHeader() != nil {
                return try postStreamable(body: body, deadline: deadline, allowAuthRetry: false)
            }
            throw MCPHTTPProberError.unauthorized
        }
        // Failover signals: the server doesn't speak StreamableHTTP at this endpoint.
        if [404, 405, 406, 415].contains(stream.statusCode) {
            stream.cancel()
            throw MCPHTTPProberError.unsupported(statusCode: stream.statusCode)
        }
        guard (200..<300).contains(stream.statusCode) else {
            let body = drain(stream, deadline: deadline)
            stream.cancel()
            throw MCPHTTPProberError.responseError(
                statusCode: stream.statusCode,
                body: MCPOAuthFlow.previewBody(body)
            )
        }
        captureSessionID(from: stream.headerFields)

        let contentType = stream.contentTypeMediaType ?? ""
        if contentType.hasPrefix("text/event-stream") {
            return .sse(stream)
        }
        // Buffer a JSON (or empty) response body.
        let data = drain(stream, deadline: deadline)
        stream.cancel()
        if data.isEmpty {
            // 202 Accepted with no body (e.g. a notification ack) → empty result object.
            return .json([:])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            // Non-JSON success body (e.g. an HTML page from a reverse proxy) → failover.
            throw MCPHTTPProberError.unsupported(statusCode: stream.statusCode)
        }
        return .json(object)
    }

    private func streamableHeaders() -> [String: String] {
        var headers = extraHeaders
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json, text/event-stream"
        headers["MCP-Protocol-Version"] = protocolVersion
        if let sessionID { headers["Mcp-Session-Id"] = sessionID }
        if let auth = authorization.currentAuthorizationHeader() { headers["Authorization"] = auth }
        return headers
    }

    // MARK: - HTTP+SSE fallback (2024-11-05)

    private func httpSSERequest(body: Data, id: Int, deadline: Date) throws -> [String: Any] {
        // Establish (once) the single long-lived server→client SSE stream and the POST endpoint.
        let messageEndpoint = try ensureSSEMessageEndpoint(deadline: deadline)
        guard let stream = sseStream else {
            throw MCPHTTPProberError.transport("the MCP SSE stream is not connected.")
        }
        // POST the request first; its JSON-RPC reply then arrives on the shared SSE stream.
        _ = try postMessage(to: messageEndpoint, body: body, expectResponse: true, deadline: deadline)
        return try readMatchingResponse(fromSSE: stream, parser: &sseParser, id: id, deadline: deadline)
    }

    /// Open the persistent server→client SSE stream (once) and read its `endpoint` event to learn
    /// where to POST. The stream and its parser are retained for all subsequent replies.
    private func ensureSSEMessageEndpoint(deadline: Date) throws -> URL {
        if let sseMessageEndpoint { return sseMessageEndpoint }
        let stream = try openSSEStream(deadline: deadline)
        sseStream = stream
        while Date() < deadline {
            guard let chunk = try readChunk(from: stream, deadline: deadline) else {
                break
            }
            for event in try sseParser.append(chunk) where event.event == "endpoint" {
                guard let resolved = resolveEndpointURL(event.data) else { continue }
                sseMessageEndpoint = resolved
                return resolved
            }
        }
        stream.cancel()
        sseStream = nil
        throw MCPHTTPProberError.transport("the MCP server did not advertise an SSE message endpoint.")
    }

    private func openSSEStream(deadline: Date, allowAuthRetry: Bool = true) throws -> MCPHTTPStream {
        var headers = extraHeaders
        headers["Accept"] = "text/event-stream"
        if let auth = authorization.currentAuthorizationHeader() { headers["Authorization"] = auth }
        let request = MCPHTTPRequest(
            url: endpoint,
            method: "GET",
            headers: headers,
            timeout: remaining(until: deadline)
        )
        let stream: MCPHTTPStream
        do {
            stream = try httpClient.openStream(request)
        } catch let error as MCPHTTPClientError {
            throw MCPHTTPProberError.transport(error.description)
        }
        // 401 → refresh once, retry once. `allowAuthRetry` caps this at a single retry so a
        // server that always 401s (audience mismatch / clock skew / hostile) while its token
        // endpoint keeps answering refresh cannot drive unbounded recursion + a refresh flood.
        if stream.statusCode == 401 {
            stream.cancel()
            if allowAuthRetry, authorization.refreshAuthorizationHeader() != nil {
                return try openSSEStream(deadline: deadline, allowAuthRetry: false)
            }
            throw MCPHTTPProberError.unauthorized
        }
        guard (200..<300).contains(stream.statusCode) else {
            stream.cancel()
            throw MCPHTTPProberError.responseError(statusCode: stream.statusCode, body: "")
        }
        return stream
    }

    /// POST a client→server message to the SSE message endpoint. The HTTP response body is an ack
    /// (the actual JSON-RPC reply comes over the SSE stream), so we only check the status.
    @discardableResult
    private func postMessage(
        to url: URL,
        body: Data,
        expectResponse: Bool,
        deadline: Date,
        allowAuthRetry: Bool = true
    ) throws -> Data {
        var headers = extraHeaders
        headers["Content-Type"] = "application/json"
        if let auth = authorization.currentAuthorizationHeader() { headers["Authorization"] = auth }
        let request = MCPHTTPRequest(
            url: url,
            method: "POST",
            headers: headers,
            body: body,
            timeout: remaining(until: deadline),
            maxResponseBytes: MCPStdioMessageCodec.maxMessageBytes
        )
        let response: MCPHTTPResponse
        do {
            response = try httpClient.perform(request)
        } catch let error as MCPHTTPClientError {
            throw MCPHTTPProberError.transport(error.description)
        }
        // 401 → refresh once, retry once (bounded by `allowAuthRetry`); never recurse
        // unbounded on a server that perpetually 401s while refresh keeps succeeding.
        if response.statusCode == 401 {
            if allowAuthRetry, authorization.refreshAuthorizationHeader() != nil {
                return try postMessage(
                    to: url,
                    body: body,
                    expectResponse: expectResponse,
                    deadline: deadline,
                    allowAuthRetry: false
                )
            }
            throw MCPHTTPProberError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MCPHTTPProberError.responseError(
                statusCode: response.statusCode,
                body: MCPOAuthFlow.previewBody(response.body)
            )
        }
        return response.body
    }

    /// Resolve the `endpoint` event's payload (which may be an absolute URL or an origin-relative
    /// path) against the SSE endpoint's origin. Rejects a payload that escapes to another origin.
    private func resolveEndpointURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            // Only accept an absolute endpoint on the same origin as the configured server.
            guard let a = try? MCPOAuthFlow.origin(of: absolute),
                  let b = try? MCPOAuthFlow.origin(of: endpoint),
                  a == b else {
                return nil
            }
            return absolute
        }
        return URL(string: trimmed, relativeTo: endpoint)?.absoluteURL
    }

    // MARK: - SSE response reading

    /// Read SSE frames until a JSON-RPC response with the given id arrives, honouring the
    /// deadline. Server→client requests/notifications on the stream are skipped. The parser is
    /// passed in so the HTTP+SSE fallback can carry partial frames across successive requests on
    /// its shared long-lived stream.
    private func readMatchingResponse(
        fromSSE stream: MCPHTTPStream,
        parser: inout MCPSSEParser,
        id: Int,
        deadline: Date
    ) throws -> [String: Any] {
        while Date() < deadline {
            guard let chunk = try readChunk(from: stream, deadline: deadline) else {
                break // clean end of stream without our response
            }
            for event in try parser.append(chunk) {
                // JSON-RPC replies arrive as "message" events (the SSE default). Skip the
                // "endpoint" discovery event and any other named control events.
                guard event.event == "message" else { continue }
                guard let data = event.data.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    continue
                }
                if Self.messageMatchesID(object, id: id) {
                    return try Self.extractResult(from: object, matchingID: id)
                }
            }
        }
        throw MCPHTTPProberError.timeout
    }

    private func readChunk(from stream: MCPHTTPStream, deadline: Date) throws -> Data? {
        do {
            return try stream.readChunk(timeout: remaining(until: deadline))
        } catch let error as MCPHTTPClientError {
            if error == .timedOut { throw MCPHTTPProberError.timeout }
            throw MCPHTTPProberError.transport(error.description)
        }
    }

    private func drain(_ stream: MCPHTTPStream, deadline: Date) -> Data {
        var data = Data()
        while data.count < MCPStdioMessageCodec.maxMessageBytes {
            guard let chunk = ((try? stream.readChunk(timeout: remaining(until: deadline))) ?? nil),
                  !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        return data
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

    // MARK: - Framing helpers

    private func captureSessionID(from headers: [String: String]) {
        if let value = headers["mcp-session-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            sessionID = value
        }
    }

    private func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func remaining(until deadline: Date) -> TimeInterval {
        max(0.1, deadline.timeIntervalSinceNow)
    }

    static func messageMatchesID(_ object: [String: Any], id: Int) -> Bool {
        if let value = object["id"] as? Int { return value == id }
        if let value = object["id"] as? NSNumber { return value.intValue == id }
        if let value = object["id"] as? String { return value == "\(id)" }
        return false
    }

    static func extractResult(from object: [String: Any], matchingID id: Int) throws -> [String: Any] {
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "MCP server returned an error."
            throw MCPProbeError.responseError(message)
        }
        guard let result = object["result"] as? [String: Any] else {
            throw MCPProbeError.invalidMessage("MCP response did not include a result object.")
        }
        return result
    }
}

/// Internal transport-level errors, separate from the public `MCPProbeError` so the request path
/// can classify a StreamableHTTP failover signal without leaking that to callers.
enum MCPHTTPProberError: Error, CustomStringConvertible {
    case transport(String)
    case unauthorized
    case unsupported(statusCode: Int)
    case responseError(statusCode: Int, body: String)
    case timeout

    var isFailoverSignal: Bool {
        if case .unsupported = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .transport(let message):
            return message
        case .unauthorized:
            return "the MCP server rejected the request as unauthorized (401) and the session could not be refreshed."
        case .unsupported(let statusCode):
            return "the MCP server does not support this transport (HTTP \(statusCode))."
        case .responseError(let statusCode, let body):
            return body.isEmpty
                ? "the MCP server returned HTTP \(statusCode)."
                : "the MCP server returned HTTP \(statusCode): \(body)"
        case .timeout:
            return "the MCP server did not respond before the request timed out."
        }
    }
}
