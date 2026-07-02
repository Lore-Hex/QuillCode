import Foundation
import XCTest
@testable import QuillCodeCore
@testable import QuillCodeTools

final class MCPHTTPProberTests: XCTestCase {
    private let endpoint = URL(string: "https://mcp.example.com/mcp")!

    // MARK: StreamableHTTP with a JSON response body

    func testStreamableHTTPProbeParsesJSONResponses() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            let method = body["method"] as? String
            switch method {
            case "initialize":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "protocolVersion": "2025-03-26",
                    "serverInfo": ["name": "Remote MCP", "version": "2.0.0"],
                    "capabilities": ["tools": [:]]
                ]), sessionID: "sess-123")
            case "notifications/initialized":
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            case "tools/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "tools": [["name": "search", "description": "Search the web"]]
                ]))
            default:
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [:]))
            }
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        let result = try prober.probe(timeout: 2.0)

        XCTAssertEqual(result.protocolVersion, "2025-03-26")
        XCTAssertEqual(result.serverName, "Remote MCP")
        XCTAssertEqual(result.serverVersion, "2.0.0")
        XCTAssertEqual(result.toolNames, ["search"])
        XCTAssertEqual(result.toolDescriptors.first?.description, "Search the web")
        // The session id from the initialize response is echoed on subsequent requests.
        let toolsRequest = client.requests.first { ($0.body.flatMap(Self.method)) == "tools/list" }
        XCTAssertEqual(toolsRequest?.headers["Mcp-Session-Id"], "sess-123")
    }

    // MARK: StreamableHTTP with an SSE response body

    func testStreamableHTTPProbeParsesSSEResponses() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            let id = body["id"]
            let object = Self.result(id: id, Self.resultPayload(for: body["method"] as? String))
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            if (body["method"] as? String) == "notifications/initialized" {
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            }
            // Deliver the JSON-RPC reply as an SSE "message" event, split across two chunks to
            // exercise partial-frame reassembly.
            let frame = "event: message\ndata: \(json)\n\n"
            let mid = frame.index(frame.startIndex, offsetBy: frame.count / 2)
            return MCPHTTPStubStream.sse([String(frame[..<mid]), String(frame[mid...])])
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        let result = try prober.probe(timeout: 2.0)
        XCTAssertEqual(result.serverName, "Remote MCP")
        XCTAssertEqual(result.toolNames, ["search"])

        let call = try prober.callTool(toolName: "search", argumentsJSON: #"{"q":"swift"}"#, timeout: 2.0)
        XCTAssertTrue(call.ok, call.error ?? "")
        XCTAssertEqual(call.stdout, "hello from remote MCP")
    }

    // Regression (BLOCKER 2): a StreamableHTTP server that emits its SSE reply with CRLF between
    // fields (spec-permitted) must be parsed, not dropped-then-timed-out.
    func testStreamableHTTPProbeParsesCRLFSSEResponses() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            if (body["method"] as? String) == "notifications/initialized" {
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            }
            let object = Self.result(id: body["id"], Self.resultPayload(for: body["method"] as? String))
            let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            // CRLF BETWEEN fields and as the frame terminator.
            return MCPHTTPStubStream.sse(["event: message\r\ndata: \(json)\r\n\r\n"])
        }
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        let result = try prober.probe(timeout: 2.0)
        XCTAssertEqual(result.serverName, "Remote MCP")
        XCTAssertEqual(result.toolNames, ["search"])
    }

    // MARK: Failover from StreamableHTTP to HTTP+SSE

    func testFailsOverToHTTPSSEWhenStreamableRejected() throws {
        let client = MCPHTTPStubClient()
        let messagePath = "/messages?session=abc"
        // One shared long-lived SSE stream, exactly like a real HTTP+SSE server: the GET returns
        // it, and each message POST pushes the matching JSON-RPC reply onto it.
        let liveStream = MCPHTTPLiveStubStream()
        liveStream.pushEvent(name: "endpoint", data: messagePath)

        client.onStream { request in
            if request.method == "POST" {
                // StreamableHTTP POST is rejected → triggers failover to HTTP+SSE.
                return MCPHTTPStubStream(statusCode: 405, headerFields: [:], chunks: [.success(nil)])
            }
            return liveStream // GET → the shared server→client stream
        }
        client.onPerform { request in
            XCTAssertTrue(request.url.absoluteString.contains("/messages"))
            guard let body = request.body,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return MCPHTTPResponse(statusCode: 400)
            }
            // Notifications carry no id and get no reply.
            if let id = object["id"] {
                let method = object["method"] as? String
                let payload: [String: Any] = method == "initialize"
                    ? ["protocolVersion": "2024-11-05", "serverInfo": ["name": "Legacy MCP"], "capabilities": [:]]
                    : Self.resultPayload(for: method)
                let reply = Self.result(id: id, payload)
                guard let data = try? JSONSerialization.data(withJSONObject: reply) else {
                    return MCPHTTPResponse(statusCode: 500)
                }
                let json = String(decoding: data, as: UTF8.self)
                liveStream.pushEvent(name: "message", data: json)
            }
            return MCPHTTPResponse(statusCode: 202)
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        let result = try prober.probe(timeout: 3.0)
        XCTAssertEqual(result.serverName, "Legacy MCP")
        XCTAssertEqual(result.toolNames, ["search"])
    }

    // MARK: 401 → refresh → retry once

    func testUnauthorizedTriggersSingleRefreshAndRetry() throws {
        let auth = CountingAuthorization(initialHeader: "Bearer old", refreshedHeader: "Bearer new")
        let client = MCPHTTPStubClient()
        let attempts = LockedInt()

        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            if (body["method"] as? String) == "initialize" {
                let count = attempts.increment()
                if count == 1 {
                    // First initialize is unauthorized.
                    XCTAssertEqual(request.headers["Authorization"], "Bearer old")
                    return MCPHTTPStubStream(statusCode: 401, headerFields: [:], chunks: [.success(nil)])
                }
                // Retry carries the refreshed token.
                XCTAssertEqual(request.headers["Authorization"], "Bearer new")
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "protocolVersion": "2025-03-26",
                    "serverInfo": ["name": "Auth MCP"],
                    "capabilities": [:]
                ]))
            }
            return MCPHTTPStubStream.json(Self.result(id: body["id"], ["tools": []]))
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client, authorization: auth)
        let result = try prober.probe(timeout: 2.0)
        XCTAssertEqual(result.serverName, "Auth MCP")
        XCTAssertEqual(auth.refreshCount, 1, "refresh must happen exactly once")
    }

    func testUnauthorizedWithoutRefreshFailsWithoutLooping() throws {
        let client = MCPHTTPStubClient()
        let attempts = LockedInt()
        client.onStream { _ in
            _ = attempts.increment()
            return MCPHTTPStubStream(statusCode: 401, headerFields: [:], chunks: [.success(nil)])
        }
        // No-auth provider: refreshAuthorizationHeader returns nil → no retry.
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        XCTAssertThrowsError(try prober.probe(timeout: 2.0))
        XCTAssertEqual(attempts.value, 1, "a 401 with no refresh must not retry")
    }

    // Regression (BLOCKER 1): a server whose SSE GET perpetually 401s while refresh always
    // succeeds must surface the 401 after exactly ONE refresh+retry — not recurse unbounded
    // (stack overflow) or flood the token endpoint with refreshes.
    func testHTTPSSEGetPerpetual401RefreshesExactlyOnce() {
        let auth = CountingAuthorization(initialHeader: "Bearer old", refreshedHeader: "Bearer new")
        let client = MCPHTTPStubClient()
        let getAttempts = LockedInt()
        client.onStream { request in
            XCTAssertEqual(request.method, "GET") // httpSSE opens a GET stream first
            _ = getAttempts.increment()
            return MCPHTTPStubStream(statusCode: 401, headerFields: [:], chunks: [.success(nil)])
        }
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client, authorization: auth, mode: .httpSSE)
        XCTAssertThrowsError(try prober.probe(timeout: 2.0))
        XCTAssertEqual(auth.refreshCount, 1, "a perpetual 401 must refresh exactly once")
        XCTAssertEqual(getAttempts.value, 2, "one original attempt + one retry, then stop")
    }

    // Regression (BLOCKER 1): same bound on the HTTP+SSE message POST path. The SSE GET succeeds
    // and advertises the endpoint, but the message POST perpetually 401s; refresh always
    // succeeds. Must refresh exactly once for the POST, then surface the 401.
    func testHTTPSSEPostPerpetual401RefreshesExactlyOnce() {
        let auth = CountingAuthorization(initialHeader: "Bearer old", refreshedHeader: "Bearer new")
        let client = MCPHTTPStubClient()
        let postAttempts = LockedInt()
        // A live SSE stream that only ever advertises the endpoint (never a reply).
        let liveStream = MCPHTTPLiveStubStream()
        liveStream.pushEvent(name: "endpoint", data: "/messages")

        client.onStream { request in
            XCTAssertEqual(request.method, "GET")
            return liveStream
        }
        client.onPerform { _ in
            _ = postAttempts.increment()
            return MCPHTTPResponse(statusCode: 401)
        }
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client, authorization: auth, mode: .httpSSE)
        XCTAssertThrowsError(try prober.probe(timeout: 2.0))
        XCTAssertEqual(auth.refreshCount, 1, "a perpetual 401 on the message POST must refresh exactly once")
        XCTAssertEqual(postAttempts.value, 2, "one original POST + one retry, then stop")
    }

    // MARK: Malformed SSE — huge frame is rejected, not buffered unbounded

    func testMalformedHugeSSEFrameIsBounded() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            if (body["method"] as? String) == "initialize" {
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "serverInfo": ["name": "MCP"], "capabilities": [:]
                ]))
            }
            if (body["method"] as? String) == "notifications/initialized" {
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            }
            // tools/list: an SSE frame that never terminates and exceeds the cap.
            let huge = String(repeating: "x", count: 9 * 1024 * 1024)
            return MCPHTTPStubStream(
                statusCode: 200,
                headerFields: ["content-type": "text/event-stream"],
                chunks: [.success(Data("data: \(huge)".utf8)), .success(nil)]
            )
        }
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        // The oversized frame must throw rather than hang or OOM.
        XCTAssertThrowsError(try prober.probe(timeout: 2.0))
    }

    // MARK: Helpers

    private static func result(id: Any?, _ payload: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": payload]
    }

    private static func resultPayload(for method: String?) -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2025-03-26",
                "serverInfo": ["name": "Remote MCP", "version": "2.0.0"],
                "capabilities": ["tools": [:]]
            ]
        case "tools/list":
            return ["tools": [["name": "search"]]]
        case "tools/call":
            return ["content": [["type": "text", "text": "hello from remote MCP"]], "isError": false]
        default:
            return [:]
        }
    }

    private static func method(_ body: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["method"] as? String
    }
}

// MARK: - Test doubles

private func XCTUnwrapMessage(
    _ body: Data?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [String: Any] {
    guard let body,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw MCPProbeError.invalidMessage("request body was not a JSON object")
    }
    return object
}

private final class CountingAuthorization: MCPRemoteAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var header: String
    private let refreshedHeader: String
    private(set) var refreshCount = 0

    init(initialHeader: String, refreshedHeader: String) {
        self.header = initialHeader
        self.refreshedHeader = refreshedHeader
    }

    func currentAuthorizationHeader() -> String? {
        lock.lock(); defer { lock.unlock() }
        return header
    }

    func refreshAuthorizationHeader() -> String? {
        lock.lock(); defer { lock.unlock() }
        refreshCount += 1
        header = refreshedHeader
        return header
    }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; _value += 1; return _value }
}
