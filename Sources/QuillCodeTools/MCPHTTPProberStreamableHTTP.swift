import Foundation

extension MCPHTTPProber {
    // MARK: - StreamableHTTP

    func streamableRequest(
        body: Data,
        id: Int,
        method: String,
        params: [String: Any],
        deadline: Date,
        progressObserver: MCPProgressObserver? = nil,
        elicitationHandler: MCPClientElicitationHandler? = nil
    ) throws -> [String: Any] {
        let outcome = try postStreamable(body: body, deadline: deadline, allowAuthRetry: true)
        switch outcome {
        case .json(let object):
            return try Self.extractResult(from: object, matchingID: id)
        case .sse(let stream):
            defer { stream.cancel() }
            // A StreamableHTTP POST returns a fresh, per-request SSE stream, so a fresh parser.
            var parser = MCPSSEParser(maxEventBytes: MCPStdioMessageCodec.maxMessageBytes)
            return try readMatchingResponse(
                fromSSE: stream,
                parser: &parser,
                id: id,
                deadline: deadline,
                progressObserver: progressObserver,
                elicitationHandler: elicitationHandler,
                responseTransport: .streamableHTTP
            )
        }
    }

    enum PostOutcome {
        case json([String: Any])
        case sse(MCPHTTPStream)
    }

    /// POST a JSON-RPC body under StreamableHTTP, handling a single 401 auth refresh+retry and
    /// classifying failover signals. Reads the response as JSON or an SSE stream by content type.
    func postStreamable(body: Data, deadline: Date, allowAuthRetry: Bool) throws -> PostOutcome {
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

    func streamableHeaders() -> [String: String] {
        var headers = extraHeaders
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json, text/event-stream"
        headers["MCP-Protocol-Version"] = protocolVersion
        if let sessionID { headers["Mcp-Session-Id"] = sessionID }
        if let auth = authorization.currentAuthorizationHeader() { headers["Authorization"] = auth }
        return headers
    }
}
