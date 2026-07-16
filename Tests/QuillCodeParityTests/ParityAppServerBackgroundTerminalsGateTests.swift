import XCTest

final class ParityAppServerBackgroundTerminalsGateTests: QuillCodeParityTestCase {
    func testBackgroundTerminalsStayWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let terminals = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionBackgroundTerminals.swift"
        )
        let userShell = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionUserShell.swift"
        )
        let tests = try text(root, "Tests/QuillCodeCLITests/AppServerUserShellTests.swift")
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "thread/backgroundTerminals/list",
            "thread/backgroundTerminals/terminate",
            "thread/backgroundTerminals/clean"
        ])
        Self.assertSource(terminals, containsAll: [
            "processIdentifier",
            "nextCursor",
            "requestUserShellCommandTermination"
        ])
        Self.assertSource(userShell, contains: "terminationRequested")
        Self.assertSource(
            tests,
            contains: "testBackgroundTerminalsListPaginatesTerminatesAndCleans"
        )
        Self.assertSource(smoke, contains: "background shell never became listable")
        Self.assertSource(parity, contains: "App-server background terminals")
        Self.assertSource(research, contains: "thread/backgroundTerminals/list")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
