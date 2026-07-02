import Foundation
import XCTest
@testable import QuillCodeTools

/// End-to-end test against a REAL sourcekit-lsp. It is skipped (not failed) when sourcekit-lsp is not
/// installed, so CI without a Swift toolchain LSP stays green — the deterministic stub tests carry
/// the correctness load. Run locally with a toolchain present to exercise the real transport.
final class LSPSourceKitIntegrationTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(sourceKitLSPAvailable, "sourcekit-lsp not found on PATH / via xcrun; skipping integration test")
        workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-lsp-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        workspace = workspace.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
    }

    private var sourceKitLSPAvailable: Bool {
        LSPCommandLocator().locate(command: "sourcekit-lsp") != nil
    }

    func testRealServerHandshakeAndDefinition() throws {
        let registry = LSPServerRegistry()
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry)

        let file = workspace.appendingPathComponent("Main.swift")
        try Data("""
        struct Point { var x: Int }
        let p = Point(x: 1)
        print(p.x)
        """.utf8).write(to: file)

        let client = try XCTUnwrap(manager.client(forPath: file.path), "server should launch and initialize")
        try client.didOpen(path: file.path, text: try String(contentsOf: file, encoding: .utf8), languageID: "swift")
        // A real server may take a moment; a bounded request must return without hanging the test.
        let symbols = try client.documentSymbols(path: file.path, timeout: 15)
        XCTAssertTrue(symbols.contains { $0.name == "Point" }, "expected the Point struct in document symbols")
        manager.shutdown()
    }
}
