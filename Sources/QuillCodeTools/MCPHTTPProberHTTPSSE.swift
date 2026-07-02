import Foundation

extension MCPHTTPProber {
    // MARK: - HTTP+SSE fallback (2024-11-05)

    func httpSSERequest(body: Data, id: Int, deadline: Date) throws -> [String: Any] {
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
    func ensureSSEMessageEndpoint(deadline: Date) throws -> URL {
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

    func openSSEStream(deadline: Date, allowAuthRetry: Bool = true) throws -> MCPHTTPStream {
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
    func postMessage(
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
    func resolveEndpointURL(_ value: String) -> URL? {
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
}
