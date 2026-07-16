import Foundation

extension MCPHTTPProber {
    // MARK: - SSE response reading

    /// Read SSE frames until a JSON-RPC response with the given id arrives, honouring the
    /// deadline. Server→client requests/notifications on the stream are skipped. The parser is
    /// passed in so the HTTP+SSE fallback can carry partial frames across successive requests on
    /// its shared long-lived stream.
    func readMatchingResponse(
        fromSSE stream: MCPHTTPStream,
        parser: inout MCPSSEParser,
        id: Int,
        deadline: Date,
        progressObserver: MCPProgressObserver? = nil
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
                progressObserver?.receive(object)
            }
        }
        throw MCPHTTPProberError.timeout
    }

    func readChunk(from stream: MCPHTTPStream, deadline: Date) throws -> Data? {
        do {
            return try stream.readChunk(timeout: remaining(until: deadline))
        } catch let error as MCPHTTPClientError {
            if error == .timedOut { throw MCPHTTPProberError.timeout }
            throw MCPHTTPProberError.transport(error.description)
        }
    }

    func drain(_ stream: MCPHTTPStream, deadline: Date) -> Data {
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

    // MARK: - Framing helpers

    func captureSessionID(from headers: [String: String]) {
        if let value = headers["mcp-session-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            sessionID = value
        }
    }

    func remaining(until deadline: Date) -> TimeInterval {
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
