import Foundation
import XCTest
@testable import QuillCodeTools

final class LSPClientTests: XCTestCase {
    private let workspace = URL(fileURLWithPath: "/tmp/quillcode-lsp-test")

    func testInitializeHandshakeSendsInitializeAndInitialized() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": ["documentFormattingProvider": true]])
        let client = LSPClient(transport: transport)

        let capabilities = try client.initialize(workspaceRoot: workspace)
        XCTAssertTrue(client.supportsFormatting)
        XCTAssertNotNil(capabilities["documentFormattingProvider"])

        // The client must have sent an `initialize` request followed by an `initialized` notification.
        let methods = transport.sentMessages.compactMap { $0["method"] as? String }
        XCTAssertEqual(methods, ["initialize", "initialized"])
        let initialize = try XCTUnwrap(transport.sentMessages.first)
        XCTAssertEqual(initialize["id"] as? Int, 1)
        let params = try XCTUnwrap(initialize["params"] as? [String: Any])
        XCTAssertNotNil(params["rootUri"])
    }

    func testInitializeIsIdempotent() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)
        try client.initialize(workspaceRoot: workspace) // second call is a no-op
        XCTAssertEqual(transport.sentMessages.filter { $0["method"] as? String == "initialize" }.count, 1)
    }

    func testDefinitionParsesLocations() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        transport.enqueueResponse(id: 2, result: [[
            "uri": "file:///tmp/quillcode-lsp-test/Foo.swift",
            "range": ["start": ["line": 10, "character": 4], "end": ["line": 10, "character": 8]]
        ]])
        let locations = try client.definition(path: "/tmp/quillcode-lsp-test/Bar.swift", line: 3, character: 2)
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations.first?.range.start.line, 10)
        XCTAssertEqual(locations.first?.uri, "file:///tmp/quillcode-lsp-test/Foo.swift")
    }

    func testReferencesIncludesContext() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        transport.enqueueResponse(id: 2, result: [
            ["uri": "file:///a.swift", "range": ["start": ["line": 1, "character": 0], "end": ["line": 1, "character": 3]]],
            ["uri": "file:///b.swift", "range": ["start": ["line": 5, "character": 2], "end": ["line": 5, "character": 5]]]
        ])
        let refs = try client.references(path: "/tmp/quillcode-lsp-test/x.swift", line: 2, character: 1)
        XCTAssertEqual(refs.count, 2)
        let request = try XCTUnwrap(transport.sentMessages.last)
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        let context = try XCTUnwrap(params["context"] as? [String: Any])
        XCTAssertEqual(context["includeDeclaration"] as? Bool, true)
    }

    func testHoverFlattensMarkupContent() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        transport.enqueueResponse(id: 2, result: ["contents": ["kind": "markdown", "value": "func foo() -> Int"]])
        let hover = try client.hover(path: "/tmp/quillcode-lsp-test/x.swift", line: 1, character: 1)
        XCTAssertEqual(hover, "func foo() -> Int")
    }

    func testDocumentSymbolFlattensTree() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        transport.enqueueResponse(id: 2, result: [[
            "name": "Widget",
            "kind": 5, // class
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 20, "character": 0]],
            "selectionRange": ["start": ["line": 0, "character": 6], "end": ["line": 0, "character": 12]],
            "children": [[
                "name": "render",
                "kind": 6, // method
                "range": ["start": ["line": 2, "character": 4], "end": ["line": 4, "character": 4]],
                "selectionRange": ["start": ["line": 2, "character": 9], "end": ["line": 2, "character": 15]]
            ]]
        ]])
        let symbols = try client.documentSymbols(path: "/tmp/quillcode-lsp-test/Widget.swift")
        XCTAssertEqual(symbols.map(\.name), ["Widget", "render"])
        XCTAssertEqual(symbols.first?.kindLabel, "class")
        XCTAssertEqual(symbols.last?.containerName, "Widget")
    }

    func testWorkspaceSymbolParsesInformation() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        transport.enqueueResponse(id: 2, result: [[
            "name": "ToolRouter",
            "kind": 23, // struct
            "location": ["uri": "file:///tmp/quillcode-lsp-test/ToolRouter.swift", "range": ["start": ["line": 3, "character": 0], "end": ["line": 3, "character": 10]]]
        ]])
        let symbols = try client.workspaceSymbols(query: "ToolRouter")
        XCTAssertEqual(symbols.first?.name, "ToolRouter")
        XCTAssertEqual(symbols.first?.kindLabel, "struct")
    }

    func testDiagnosticsCollectedFromPublishNotification() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        let uri = "file:///tmp/quillcode-lsp-test/Broken.swift"
        transport.enqueueDiagnostics(uri: uri, diagnostics: [[
            "range": ["start": ["line": 4, "character": 0], "end": ["line": 4, "character": 5]],
            "severity": 1,
            "message": "cannot find 'foo' in scope"
        ]])
        let diagnostics = client.diagnostics(for: "/tmp/quillcode-lsp-test/Broken.swift", waitFor: 0.5)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.severity, .error)
        XCTAssertEqual(diagnostics.first?.message, "cannot find 'foo' in scope")
    }

    func testServerErrorResponseThrows() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        transport.enqueueError(id: 2, code: -32601, message: "method not found")
        XCTAssertThrowsError(try client.definition(path: "/tmp/quillcode-lsp-test/x.swift", line: 1, character: 0)) { error in
            guard case LSPError.serverError(let code, _) = error else { return XCTFail("expected serverError") }
            XCTAssertEqual(code, -32601)
        }
    }

    func testTimeoutWhenServerNeverResponds() {
        let transport = ScriptedLSPTransport() // never enqueues an initialize response
        let client = LSPClient(transport: transport)
        XCTAssertThrowsError(try client.initialize(workspaceRoot: workspace, timeout: 0.3)) { error in
            guard case LSPError.timeout = error else { return XCTFail("expected timeout, got \(error)") }
        }
    }

    func testEOFWhileAwaitingResponseThrowsServerClosed() {
        let transport = ScriptedLSPTransport()
        transport.close() // server exits immediately, no response
        let client = LSPClient(transport: transport)
        XCTAssertThrowsError(try client.initialize(workspaceRoot: workspace, timeout: 1.0)) { error in
            guard case LSPError.serverClosed = error else { return XCTFail("expected serverClosed, got \(error)") }
        }
    }

    func testMalformedFramePoisonsClient() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)
        XCTAssertTrue(client.isHealthy)

        // The server leaks a non-protocol line to stdout (a bad Content-Length). The bytes stay at the
        // front of the buffer, so the request throws — and the client must mark itself poisoned so the
        // session is dropped rather than replaying the corrupt prefix on every future request.
        transport.enqueueRaw(Data("Content-Length: not-a-number\r\n\r\n".utf8))
        XCTAssertThrowsError(try client.definition(path: "/tmp/quillcode-lsp-test/x.swift", line: 1, character: 0))
        XCTAssertFalse(client.isHealthy, "a codec error must poison the client so the manager relaunches it")

        // Even a subsequently-queued valid response is unreachable — the client is dead until relaunch.
        transport.enqueueResponse(id: 3, result: [])
        XCTAssertThrowsError(try client.definition(path: "/tmp/quillcode-lsp-test/x.swift", line: 1, character: 0))
        XCTAssertFalse(client.isHealthy)
    }

    func testServerRequestWithCollidingIdIsNotMistakenForResponse() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        // The server sends a REQUEST (has `method` AND `id`) whose id numerically equals our next
        // request id (2), then the real response. The client must skip the request and return the
        // actual response, not the request masquerading as one.
        transport.enqueue([
            "jsonrpc": "2.0",
            "id": 2, // collides with our definition request id
            "method": "workspace/configuration",
            "params": ["items": []]
        ])
        transport.enqueueResponse(id: 2, result: [[
            "uri": "file:///tmp/quillcode-lsp-test/real.swift",
            "range": ["start": ["line": 7, "character": 0], "end": ["line": 7, "character": 4]]
        ]])
        let locations = try client.definition(path: "/tmp/quillcode-lsp-test/x.swift", line: 1, character: 0)
        XCTAssertEqual(locations.count, 1, "the server request must not be consumed as our response")
        XCTAssertEqual(locations.first?.range.start.line, 7)
    }

    func testOutOfOrderNotificationBeforeResponseIsHandled() throws {
        let transport = ScriptedLSPTransport()
        transport.enqueueResponse(id: 1, result: ["capabilities": [:]])
        let client = LSPClient(transport: transport)
        try client.initialize(workspaceRoot: workspace)

        // A publishDiagnostics notification arrives before the definition response — the client must
        // stash it and keep waiting for id 2, not mistake it for the response.
        transport.enqueueDiagnostics(uri: "file:///tmp/quillcode-lsp-test/x.swift", diagnostics: [[
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 1]],
            "severity": 2, "message": "warned"
        ]])
        transport.enqueueResponse(id: 2, result: [[
            "uri": "file:///tmp/quillcode-lsp-test/y.swift",
            "range": ["start": ["line": 1, "character": 0], "end": ["line": 1, "character": 1]]
        ]])
        let locations = try client.definition(path: "/tmp/quillcode-lsp-test/x.swift", line: 1, character: 0)
        XCTAssertEqual(locations.count, 1)
        // And the stashed diagnostic is available.
        XCTAssertEqual(client.allDiagnostics().values.first?.first?.message, "warned")
    }
}
