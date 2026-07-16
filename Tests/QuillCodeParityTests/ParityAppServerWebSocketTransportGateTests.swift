import Foundation
import XCTest

final class ParityAppServerWebSocketTransportGateTests: XCTestCase {
    func testWebSocketTransportRemainsWiredAcrossRuntimeTestsSmokeAndDocs() throws {
        let root = try packageRoot()
        let transport = try text(root, "Sources/QuillCodeCLI/AppServerWebSocketTransport.swift")
        let protocolSource = try text(root, "Sources/QuillCodeCLI/AppServerWebSocketProtocol.swift")
        let auth = try text(root, "Sources/QuillCodeCLI/AppServerWebSocketAuth.swift")
        let wire = try text(root, "Sources/QuillCodeCLI/AppServerWire.swift")
        let unix = try text(root, "Sources/QuillCodeCLI/AppServerUnixSocketTransport.swift")
        let parserTests = try text(root, "Tests/QuillCodeCLITests/CLIArgumentParserTests.swift")
        let protocolTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerWebSocketProtocolTests.swift"
        )
        let tcpSmoke = try text(root, "scripts/app-server-websocket-smoke.sh")
        let unixSmoke = try text(root, "scripts/app-server-unix-smoke.sh")
        let aggregateSmoke = try text(root, "scripts/smoke.sh")
        let parity = try text(root, "docs/CODEX_PARITY_MATRIX.md")

        assertContains(transport, "ws://")
        assertContains(transport, "/readyz")
        assertContains(transport, "/healthz")
        assertContains(transport, ".overloaded")
        assertContains(wire, "Server overloaded; retry later.")
        assertContains(protocolSource, "Sec-WebSocket-Accept")
        assertContains(protocolSource, "client frames must be masked")
        assertContains(auth, "signedBearerToken")
        assertContains(auth, "constantTimeEqual")
        assertContains(unix, "AppServerWebSocketConnectionHandler")
        assertContains(parserTests, "testAppServerParsesAndValidatesWebSocketAuth")
        assertContains(protocolTests, "testSignedBearerPolicyValidatesSignatureTimeIssuerAndAudience")
        assertContains(tcpSmoke, "app-server WebSocket smoke passed")
        assertContains(unixSmoke, "Sec-WebSocket-Key")
        assertContains(aggregateSmoke, "app-server-websocket-smoke.sh")
        assertContains(parity, "WebSocket")
    }

    private func packageRoot() throws -> URL {
        let file = URL(fileURLWithPath: #filePath)
        return file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func assertContains(
        _ source: String,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(source.contains(expected), "Missing \(expected)", file: file, line: line)
    }
}
