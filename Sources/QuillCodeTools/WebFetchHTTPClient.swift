import Foundation

/// One HTTP GET transaction for `host.web.fetch`, WITHOUT redirect following: a 3xx response
/// is returned as-is (status + `location` header) so the executor can re-run the SSRF host
/// gate on every hop. Implementations must stop reading the body once `maxBodyBytes` is
/// exceeded (streaming cap, not an after-the-fact trim) and report the overflow.
public struct WebFetchHTTPRequest: Sendable, Hashable {
    public var url: URL
    /// Header field name → value. Names are sent as given.
    public var headers: [String: String]
    /// Overall time budget for the transaction, in seconds.
    public var timeout: TimeInterval
    /// Maximum number of body bytes to read before cancelling the transfer.
    public var maxBodyBytes: Int

    public init(url: URL, headers: [String: String], timeout: TimeInterval, maxBodyBytes: Int) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.maxBodyBytes = maxBodyBytes
    }
}

public struct WebFetchHTTPResponse: Sendable, Hashable {
    public var statusCode: Int
    /// Header field names lowercased; duplicate fields joined with ", ".
    public var headerFields: [String: String]
    /// Body bytes read, at most `maxBodyBytes` of them.
    public var body: Data
    /// True when the server offered more than `maxBodyBytes` and the transfer was cut short.
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
}

public enum WebFetchHTTPClientError: Error, Sendable, Hashable, CustomStringConvertible {
    case timedOut
    case transport(String)
    case notHTTP

    public var description: String {
        switch self {
        case .timedOut:
            return "the request timed out"
        case .transport(let message):
            return message
        case .notHTTP:
            return "the server did not return an HTTP response"
        }
    }
}

public protocol WebFetchHTTPClient: Sendable {
    func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse
}
