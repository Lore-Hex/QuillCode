import XCTest

final class ParityAppServerMCPElicitationGateTests: QuillCodeParityTestCase {
    func testMCPElicitationStaysWiredAcrossTransportsAppServerSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let contract = try text(root, "Sources/QuillCodeTools/MCPClientElicitation.swift")
        let schema = try text(root, "Sources/QuillCodeTools/MCPFormElicitationSchemaValidator.swift")
        let stdio = try [
            text(root, "Sources/QuillCodeTools/MCPStdioProber.swift"),
            text(root, "Sources/QuillCodeTools/MCPStdioProberEvents.swift")
        ].joined(separator: "\n")
        let streamableHTTP = try text(root, "Sources/QuillCodeTools/MCPHTTPProberStreamableHTTP.swift")
        let legacyHTTP = try text(root, "Sources/QuillCodeTools/MCPHTTPProberHTTPSSE.swift")
        let appServer = try text(root, "Sources/QuillCodeCLI/AppServerMCPElicitation.swift")
        let directTool = try text(root, "Sources/QuillCodeCLI/AppServerMCP.swift")
        let connectionDriver = try text(
            root,
            "Sources/QuillCodeCLI/AppServerConnectionDriver.swift"
        )
        let tests = try text(root, "Tests/QuillCodeCLITests/AppServerMCPTests.swift")
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(contract, containsAll: [
            "supportsFormElicitation",
            "supportsOpenAIFormElicitation",
            "elicitation/create",
            "openai/form",
            "case form",
            "case url",
            "progressToken"
        ])
        Self.assertSource(schema, containsAll: [
            "MCPFormElicitationSchemaValidator",
            "validateProperty",
            "validateString",
            "validateNumber",
            "validateArray"
        ])
        Self.assertSource(stdio, contains: "elicitationHandler: MCPClientElicitationHandler?")
        Self.assertSource(streamableHTTP, contains: "elicitationHandler: MCPClientElicitationHandler?")
        Self.assertSource(legacyHTTP, contains: "elicitationHandler: MCPClientElicitationHandler?")
        Self.assertSource(appServer, containsAll: [
            "mcpServer/elicitation/request",
            "serverRequest/resolved",
            "requestTurnMCPElicitation",
            "resolveAllPendingMCPElicitations"
        ])
        Self.assertSource(directTool, contains: "turnID: nil")
        Self.assertSource(connectionDriver, containsAll: [
            "requestCanAwaitClientResponse",
            "mcpServer/tool/call",
            "AppServerConcurrentRequestPool"
        ])
        Self.assertSource(tests, containsAll: [
            "testDirectToolCallRelaysStandardFormElicitationAndPreservesResponseMetadata",
            "testRichFormElicitationRequiresAndAdvertisesInitializeCapability",
            "testURLElicitationRelaysExactFieldsAndClientErrorDeclines",
            "testInterruptCancelsTurnElicitationBeforeTurnCompletion"
        ])
        Self.assertSource(smoke, containsAll: [
            "mcpServerOpenaiFormElicitation",
            "mcpServer/elicitation/request",
            "serverRequest/resolved",
            "real-stdio-roundtrip"
        ])
        Self.assertSource(parity, containsAll: [
            "Server-initiated MCP elicitation",
            "mcpServer/elicitation/request",
            "serverRequest/resolved"
        ])
        XCTAssertFalse(
            parity.contains("server-initiated MCP elicitation notifications"),
            "The parity matrix must not defer implemented app-server MCP elicitation."
        )
        Self.assertSource(decisions, contains: "MCP elicitation is a bidirectional client capability")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
