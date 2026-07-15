import Foundation
@testable import QuillCodeTools
import XCTest

final class MCPHTTPHeaderInjectingClientTests: XCTestCase {
    func testAddsConfiguredHeadersWithoutOverwritingRequestSpecificFields() throws {
        let base = RecordingHeaderHTTPClient()
        let client = MCPHTTPHeaderInjectingClient(
            base: base,
            additionalHeaders: [
                "X-Tenant": "configured-tenant",
                "accept": "configured-accept"
            ]
        )
        let request = MCPHTTPRequest(
            url: URL(string: "https://example.com/token")!,
            method: "POST",
            headers: ["Accept": "application/json"]
        )

        _ = try client.perform(request)

        let recorded = try XCTUnwrap(base.lastRequest)
        XCTAssertEqual(recorded.headers["X-Tenant"], "configured-tenant")
        XCTAssertEqual(recorded.headers["Accept"], "application/json")
        XCTAssertNil(recorded.headers["accept"])
    }
}

private final class RecordingHeaderHTTPClient: MCPHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequest: MCPHTTPRequest?

    var lastRequest: MCPHTTPRequest? {
        lock.withLock { recordedRequest }
    }

    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        lock.withLock { recordedRequest = request }
        return MCPHTTPResponse(statusCode: 200)
    }

    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        lock.withLock { recordedRequest = request }
        throw MCPHTTPClientError.transport("test stream is unavailable")
    }
}
