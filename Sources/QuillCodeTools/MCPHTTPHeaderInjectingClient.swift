import Foundation

/// Decorates an MCP HTTP client with headers required by a configured remote server.
///
/// Request-specific fields win case-insensitively so OAuth helpers keep their own content
/// negotiation while gateway headers (for example, tenant routing) reach discovery,
/// registration, and token endpoints consistently with normal MCP traffic.
public struct MCPHTTPHeaderInjectingClient: MCPHTTPClient {
    private let base: any MCPHTTPClient
    private let additionalHeaders: [String: String]

    public init(
        base: any MCPHTTPClient,
        additionalHeaders: [String: String]
    ) {
        self.base = base
        self.additionalHeaders = additionalHeaders
    }

    public func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        try base.perform(addingHeaders(to: request))
    }

    public func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        try base.openStream(addingHeaders(to: request))
    }

    private func addingHeaders(to request: MCPHTTPRequest) -> MCPHTTPRequest {
        guard !additionalHeaders.isEmpty else { return request }

        var resolved = request
        let requestFieldNames = Set(request.headers.keys.map { $0.lowercased() })
        for (name, value) in additionalHeaders where !requestFieldNames.contains(name.lowercased()) {
            resolved.headers[name] = value
        }
        return resolved
    }
}
