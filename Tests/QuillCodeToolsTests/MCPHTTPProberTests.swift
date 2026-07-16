import Foundation
import XCTest
@testable import QuillCodeCore
@testable import QuillCodeTools

final class MCPHTTPProberTests: XCTestCase {
    private let endpoint = URL(string: "https://mcp.example.com/mcp")!

    func testInitializeAdvertisesConfiguredElicitationCapabilities() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            if body["method"] as? String == "notifications/initialized" {
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            }
            let payload: [String: Any] = body["method"] as? String == "initialize"
                ? ["protocolVersion": "2025-06-18", "serverInfo": ["name": "MCP"], "capabilities": [:]]
                : ["tools": []]
            return MCPHTTPStubStream.json(Self.result(id: body["id"], payload))
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        prober.configure(clientCapabilities: .init(
            supportsFormElicitation: true,
            supportsOpenAIFormElicitation: true
        ))
        _ = try prober.probe(detail: .toolsAndAuthOnly, timeout: 2)

        let request = try XCTUnwrap(
            client.requests.first { $0.body.flatMap(Self.method) == "initialize" }
        )
        let body = try XCTUnwrapMessage(request.body)
        let params = try XCTUnwrap(body["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        let extensions = try XCTUnwrap(capabilities["extensions"] as? [String: Any])
        XCTAssertEqual(params["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil(capabilities["elicitation"] as? [String: Any])
        XCTAssertNotNil(extensions["openai/form"] as? [String: Any])
    }

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
                    "capabilities": ["tools": [:], "resources": [:], "prompts": [:]]
                ]), sessionID: "sess-123")
            case "notifications/initialized":
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            case "tools/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "tools": [["name": "search", "description": "Search the web"]]
                ]))
            case "resources/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "resources": [["name": "Guide", "uri": "docs://guide", "mimeType": "text/markdown"]]
                ]))
            case "resources/templates/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "resourceTemplates": [["name": "File", "uriTemplate": "file:///{path}"]]
                ]))
            case "prompts/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "prompts": [["name": "summarize"]]
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
        XCTAssertEqual(
            result.serverInfo,
            .object(["name": .string("Remote MCP"), "version": .string("2.0.0")])
        )
        XCTAssertEqual(result.toolNames, ["search"])
        XCTAssertEqual(result.toolDescriptors.first?.description, "Search the web")
        XCTAssertEqual(result.tools.first?.objectValue?["name"], .string("search"))
        XCTAssertEqual(result.resources.first?.objectValue?["uri"], .string("docs://guide"))
        XCTAssertEqual(result.resourceTemplates.first?.objectValue?["uriTemplate"], .string("file:///{path}"))
        XCTAssertEqual(result.promptNames, ["summarize"])
        // The session id from the initialize response is echoed on subsequent requests.
        let toolsRequest = client.requests.first { ($0.body.flatMap(Self.method)) == "tools/list" }
        XCTAssertEqual(toolsRequest?.headers["Mcp-Session-Id"], "sess-123")
    }

    func testToolsAndAuthOnlyProbeSkipsResourceAndPromptRequests() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            switch body["method"] as? String {
            case "initialize":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "protocolVersion": "2025-03-26",
                    "serverInfo": ["name": "Fast MCP"],
                    "capabilities": ["tools": [:], "resources": [:], "prompts": [:]]
                ]))
            case "notifications/initialized":
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            case "tools/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "tools": [["name": "search"]]
                ]))
            default:
                XCTFail("tools-only status must not request resource or prompt inventory")
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [:]))
            }
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        let result = try prober.probe(detail: .toolsAndAuthOnly, timeout: 2.0)
        let methods = client.requests.compactMap { $0.body.flatMap(Self.method) }

        XCTAssertEqual(methods, ["initialize", "notifications/initialized", "tools/list"])
        XCTAssertEqual(result.toolNames, ["search"])
        XCTAssertTrue(result.resources.isEmpty)
        XCTAssertTrue(result.resourceTemplates.isEmpty)
        XCTAssertTrue(result.promptNames.isEmpty)
    }

    func testStreamableHTTPCallPreservesStructuredContentErrorAndMetadata() throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            switch body["method"] as? String {
            case "initialize":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "protocolVersion": "2025-03-26",
                    "serverInfo": ["name": "Remote MCP"],
                    "capabilities": ["tools": [:]]
                ]))
            case "notifications/initialized":
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            case "tools/list":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], ["tools": [["name": "search"]]]))
            case "tools/call":
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [
                    "content": [["type": "text", "text": "partial result"]],
                    "structuredContent": ["matches": 2],
                    "isError": true,
                    "_meta": ["traceID": "trace-123"]
                ]))
            default:
                return MCPHTTPStubStream.json(Self.result(id: body["id"], [:]))
            }
        }

        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        _ = try prober.probe(detail: .toolsAndAuthOnly, timeout: 2.0)
        let result = try prober.callToolResult(
            toolName: "search",
            arguments: .object(["query": .string("swift")]),
            metadata: .object(["requestID": .string("request-123")]),
            timeout: 2.0
        )
        let request = try XCTUnwrap(client.requests.first { $0.body.flatMap(Self.method) == "tools/call" })
        let body = try XCTUnwrapMessage(request.body)
        let params = try XCTUnwrap(body["params"] as? [String: Any])

        XCTAssertEqual(result.content.first?.objectValue?["text"], .string("partial result"))
        XCTAssertEqual(result.structuredContent, .object(["matches": .number(2)]))
        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(result.metadata, .object(["traceID": .string("trace-123")]))
        XCTAssertEqual((params["arguments"] as? [String: Any])?["query"] as? String, "swift")
        XCTAssertEqual((params["_meta"] as? [String: Any])?["requestID"] as? String, "request-123")
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

    func testStreamableHTTPCallEventsStreamsProgressBeforeResult() async throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            let metadata = try XCTUnwrap(params["_meta"] as? [String: Any])
            XCTAssertEqual(metadata["requestID"] as? String, "request-http")
            XCTAssertEqual(metadata["progressToken"] as? String, "progress-http")

            return MCPHTTPStubStream.sse([
                Self.sseMessage(Self.progress(token: "other", completed: 1, total: 100)),
                Self.sseMessage(Self.progress(
                    token: "progress-http",
                    completed: 20,
                    total: 100,
                    message: "Indexing"
                )),
                Self.sseMessage(Self.progress(
                    token: "progress-http",
                    completed: 80,
                    total: 100,
                    message: "Writing"
                )),
                Self.sseMessage(Self.result(id: body["id"], [
                    "content": [["type": "text", "text": "complete"]],
                    "isError": false
                ]))
            ])
        }

        var progress: [ToolExecutionProgress] = []
        var result: MCPToolCallResult?
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        for try await event in prober.callToolEvents(
            toolName: "search",
            arguments: .object(["query": .string("swift")]),
            metadata: .object([
                "requestID": .string("request-http"),
                "progressToken": .string("progress-http")
            ]),
            timeout: 2.0
        ) {
            switch event {
            case .progress(let update): progress.append(update)
            case .result(let final): result = final
            }
        }

        XCTAssertEqual(progress, [
            .init(completed: 20, total: 100, message: "Indexing"),
            .init(completed: 80, total: 100, message: "Writing")
        ])
        XCTAssertEqual(result?.content.first?.objectValue?["text"], .string("complete"))
    }

    func testStreamableHTTPCallEventsRoundTripsOpenAIFormElicitation() async throws {
        let client = MCPHTTPStubClient()
        client.onStream { request in
            let body = try XCTUnwrapMessage(request.body)
            if body["method"] == nil {
                return MCPHTTPStubStream(statusCode: 202, headerFields: [:], chunks: [.success(nil)])
            }
            return MCPHTTPStubStream.sse([
                Self.sseMessage([
                    "jsonrpc": "2.0",
                    "id": "form-http-1",
                    "method": "openai/form",
                    "params": [
                        "message": "Select a template",
                        "requestedSchema": [
                            "type": "object",
                            "properties": [
                                "template": ["type": "openai/imagePicker", "items": []]
                            ]
                        ]
                    ]
                ]),
                Self.sseMessage(Self.result(id: body["id"], [
                    "content": [["type": "text", "text": "selected"]],
                    "isError": false
                ]))
            ], sessionID: "session-forms")
        }

        let recorder = HTTPMCPElicitationRequestRecorder()
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client)
        prober.configure(clientCapabilities: .init(
            supportsFormElicitation: true,
            supportsOpenAIFormElicitation: true
        ))
        var result: MCPToolCallResult?
        for try await event in prober.callToolEvents(
            toolName: "choose_template",
            arguments: nil,
            metadata: nil,
            timeout: 2,
            elicitationHandler: { request in
                await recorder.append(request)
                return .accept(
                    content: .object(["template": .string("monthly-review")]),
                    metadata: .object(["surface": .string("test")])
                )
            }
        ) {
            if case .result(let final) = event { result = final }
        }

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        guard case .openAIForm(let message, _, _) = requests.first else {
            return XCTFail("expected OpenAI form request")
        }
        XCTAssertEqual(message, "Select a template")
        XCTAssertEqual(result?.content.first?.objectValue?["text"], .string("selected"))

        let response = try XCTUnwrap(client.requests.first { request in
            guard let body = try? XCTUnwrapMessage(request.body) else { return false }
            return body["id"] as? String == "form-http-1" && body["result"] != nil
        })
        let responseBody = try XCTUnwrapMessage(response.body)
        let payload = try XCTUnwrap(responseBody["result"] as? [String: Any])
        XCTAssertEqual(response.headers["Mcp-Session-Id"], "session-forms")
        XCTAssertEqual(payload["action"] as? String, "accept")
        XCTAssertEqual((payload["content"] as? [String: Any])?["template"] as? String, "monthly-review")
        XCTAssertEqual((payload["_meta"] as? [String: Any])?["surface"] as? String, "test")
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

    func testLegacyHTTPSSECallEventsStreamsProgressBeforeResult() async throws {
        let client = MCPHTTPStubClient()
        let liveStream = MCPHTTPLiveStubStream()
        liveStream.pushEvent(name: "endpoint", data: "/messages?session=progress")
        client.onStream { _ in liveStream }
        client.onPerform { request in
            let body = try XCTUnwrapMessage(request.body)
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            let metadata = try XCTUnwrap(params["_meta"] as? [String: Any])
            XCTAssertEqual(metadata["progressToken"] as? String, "legacy-progress")
            liveStream.pushEvent(
                name: "message",
                data: Self.json(Self.progress(token: "legacy-progress", completed: 1, total: 2, message: "Halfway"))
            )
            liveStream.pushEvent(
                name: "message",
                data: Self.json(Self.result(id: body["id"], [
                    "content": [["type": "text", "text": "legacy complete"]],
                    "isError": false
                ]))
            )
            return MCPHTTPResponse(statusCode: 202)
        }

        var events: [MCPClientToolEvent] = []
        let prober = MCPHTTPProber(
            endpoint: endpoint,
            httpClient: client,
            mode: .httpSSE
        )
        for try await event in prober.callToolEvents(
            toolName: "search",
            arguments: nil,
            metadata: .object(["progressToken": .string("legacy-progress")]),
            timeout: 2.0
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [
            .progress(.init(completed: 1, total: 2, message: "Halfway")),
            .result(.init(
                content: [.object(["text": .string("legacy complete"), "type": .string("text")])],
                isError: false
            ))
        ])
    }

    func testLegacyHTTPSSECallEventsRoundTripsFormElicitation() async throws {
        let client = MCPHTTPStubClient()
        let liveStream = MCPHTTPLiveStubStream()
        liveStream.pushEvent(name: "endpoint", data: "/messages?session=elicitation")
        client.onStream { _ in liveStream }
        client.onPerform { request in
            let body = try XCTUnwrapMessage(request.body)
            if body["method"] as? String == "tools/call" {
                liveStream.pushEvent(name: "message", data: Self.json([
                    "jsonrpc": "2.0",
                    "id": "legacy-form-1",
                    "method": "elicitation/create",
                    "params": [
                        "message": "Confirm the action",
                        "requestedSchema": [
                            "type": "object",
                            "properties": ["confirmed": ["type": "boolean"]],
                            "required": ["confirmed"]
                        ]
                    ]
                ]))
            } else if body["id"] as? String == "legacy-form-1" {
                liveStream.pushEvent(
                    name: "message",
                    data: Self.json(Self.result(id: 1, [
                        "content": [["type": "text", "text": "legacy accepted"]],
                        "isError": false
                    ]))
                )
            }
            return MCPHTTPResponse(statusCode: 202)
        }

        let recorder = HTTPMCPElicitationRequestRecorder()
        let prober = MCPHTTPProber(endpoint: endpoint, httpClient: client, mode: .httpSSE)
        prober.configure(clientCapabilities: .init(supportsFormElicitation: true))
        var result: MCPToolCallResult?
        for try await event in prober.callToolEvents(
            toolName: "confirm",
            arguments: nil,
            metadata: nil,
            timeout: 2,
            elicitationHandler: { request in
                await recorder.append(request)
                return .accept(content: .object(["confirmed": .bool(true)]))
            }
        ) {
            if case .result(let final) = event { result = final }
        }

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(result?.content.first?.objectValue?["text"], .string("legacy accepted"))
        let response = try XCTUnwrap(client.requests.first { request in
            guard let body = try? XCTUnwrapMessage(request.body) else { return false }
            return body["id"] as? String == "legacy-form-1" && body["result"] != nil
        })
        XCTAssertTrue(response.url.absoluteString.contains("/messages?session=elicitation"))
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

    private static func progress(
        token: Any,
        completed: Double,
        total: Double,
        message: String? = nil
    ) -> [String: Any] {
        var params: [String: Any] = [
            "progressToken": token,
            "progress": completed,
            "total": total
        ]
        if let message { params["message"] = message }
        return ["jsonrpc": "2.0", "method": "notifications/progress", "params": params]
    }

    private static func sseMessage(_ object: [String: Any]) -> String {
        "event: message\ndata: \(json(object))\n\n"
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func method(_ body: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["method"] as? String
    }
}

private actor HTTPMCPElicitationRequestRecorder {
    private(set) var requests: [MCPClientElicitationRequest] = []

    func append(_ request: MCPClientElicitationRequest) {
        requests.append(request)
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
