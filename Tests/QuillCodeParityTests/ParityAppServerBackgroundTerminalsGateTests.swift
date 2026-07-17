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
        let environmentTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerRemoteBackgroundTerminalTests.swift"
        )
        let transportTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerExecServerProcessSessionTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let environmentSmoke = try text(root, "scripts/app-server-environment-smoke.sh")
        let environmentFixture = try text(
            root,
            "scripts/fixtures/app_server_environment_exec_server.py"
        )
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(session, containsAll: [
            "thread/backgroundTerminals/list",
            "thread/backgroundTerminals/terminate",
            "thread/backgroundTerminals/clean"
        ])
        Self.assertSource(terminals, containsAll: [
            "backgroundProcessID",
            "osProcessID",
            "nextCursor",
            "requestUserShellCommandTermination"
        ])
        Self.assertSource(userShell, containsAll: [
            "terminationRequested",
            "remoteSessions",
            "for session in remoteSessions { await session.terminate() }"
        ])
        Self.assertSource(
            tests,
            contains: "testBackgroundTerminalsListPaginatesTerminatesAndCleans"
        )
        Self.assertSource(smoke, contains: "background shell never became listable")
        Self.assertSource(
            environmentTests,
            contains: "testRemoteUserShellStreamsListsTerminatesAndCleansThroughUnifiedRegistry"
        )
        Self.assertSource(transportTests, containsAll: [
            "testProcessSessionStreamsBeforeExitAndTerminatesTheStableProcessID",
            "testCancelledProcessReadIgnoresLateReplyWithoutResettingSharedConnection"
        ])
        Self.assertSource(environmentSmoke, containsAll: [
            "background commands completed before lifecycle inspection",
            "terminal[\"osPid\"] is None",
            "thread/backgroundTerminals/terminate",
            "thread/backgroundTerminals/clean"
        ])
        Self.assertSource(environmentFixture, containsAll: [
            "background_processes",
            "process_terminations"
        ])
        Self.assertSource(parity, contains: "App-server background terminals")
        Self.assertSource(research, containsAll: [
            "one unified process manager",
            "null `osPid`"
        ])
        Self.assertSource(decisions, contains: "Unified process boundary")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
