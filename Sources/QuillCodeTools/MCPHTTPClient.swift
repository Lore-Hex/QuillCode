import Foundation

/// One HTTP request issued by the remote MCP transport. Unlike `WebFetchHTTPRequest` (GET-only,
/// used for untrusted agent-driven fetches), this carries a method and body because the MCP
/// StreamableHTTP transport POSTs JSON-RPC and the HTTP+SSE fallback opens a long-lived GET
/// stream. The URL is user-configured in the project manifest, not agent-chosen.
public struct MCPHTTPRequest: Sendable, Hashable {
    public var url: URL
    public var method: String
    /// Header field name → value, sent as given (case preserved).
    public var headers: [String: String]
    public var body: Data?
    /// Overall time budget for a buffered (non-streaming) transaction, in seconds.
    public var timeout: TimeInterval
    /// Hard cap on how many bytes of a buffered response body are read before the transfer is
    /// cut short. SSE streams are read incrementally and are not subject to this single cap.
    public var maxResponseBytes: Int

    public init(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30,
        maxResponseBytes: Int = 8 * 1024 * 1024
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }
}

/// A fully-buffered HTTP response.
public struct MCPHTTPResponse: Sendable, Hashable {
    public var statusCode: Int
    /// Header field names lowercased; duplicate fields joined with ", ".
    public var headerFields: [String: String]
    public var body: Data
    public var bodyExceededMaxBytes: Bool

    public init(
        statusCode: Int,
        headerFields: [String: String] = [:],
        body: Data = Data(),
        bodyExceededMaxBytes: Bool = false
    ) {
        self.statusCode = statusCode
        self.headerFields = headerFields
        self.body = body
        self.bodyExceededMaxBytes = bodyExceededMaxBytes
    }

    /// Case-insensitive header lookup (fields are stored lowercased).
    public func header(_ name: String) -> String? {
        headerFields[name.lowercased()]
    }

    /// The response `Content-Type`, lowercased and stripped of parameters, e.g. `application/json`.
    public var contentTypeMediaType: String? {
        guard let raw = header("content-type") else { return nil }
        let media = raw.split(separator: ";", maxSplits: 1).first.map(String.init) ?? raw
        return media.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A streaming HTTP response whose body is delivered as chunks (used for `text/event-stream`).
/// `readChunk` returns the next block of bytes, or `nil` at end of stream, and throws on
/// transport failure or timeout. Implementations MUST honour a per-read deadline so a silent
/// server cannot hang the caller forever, and MUST bound the total bytes buffered.
public protocol MCPHTTPStream: Sendable {
    var statusCode: Int { get }
    /// Header field names lowercased.
    var headerFields: [String: String] { get }
    /// Next chunk of body bytes, or nil at clean end-of-stream. Blocks up to `timeout` seconds.
    func readChunk(timeout: TimeInterval) throws -> Data?
    /// Stop reading and release the connection.
    func cancel()
}

extension MCPHTTPStream {
    public func header(_ name: String) -> String? {
        headerFields[name.lowercased()]
    }

    public var contentTypeMediaType: String? {
        guard let raw = header("content-type") else { return nil }
        let media = raw.split(separator: ";", maxSplits: 1).first.map(String.init) ?? raw
        return media.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum MCPHTTPClientError: Error, Sendable, CustomStringConvertible, Equatable {
    case timedOut
    case transport(String)
    case notHTTP
    case responseTooLarge

    public var description: String {
        switch self {
        case .timedOut:
            return "the request timed out"
        case .transport(let message):
            return message
        case .notHTTP:
            return "the server did not return an HTTP response"
        case .responseTooLarge:
            return "the response exceeded the allowed size"
        }
    }
}

/// The HTTP transport seam the remote MCP client is built on. `perform` buffers the whole
/// response; `openStream` returns a live SSE-style stream. Tests supply a deterministic stub;
/// production uses the `URLSession`-backed implementation.
public protocol MCPHTTPClient: Sendable {
    /// Issue a request and buffer the full response body (bounded by `maxResponseBytes`).
    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse
    /// Issue a request and return a streaming response for incremental reads. Used for
    /// `Accept: text/event-stream` responses; the caller inspects the returned stream's
    /// content type and either consumes it as SSE or drains it as a buffered body.
    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream
}
