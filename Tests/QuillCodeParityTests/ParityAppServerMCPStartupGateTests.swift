import XCTest

final class ParityAppServerMCPStartupGateTests: QuillCodeParityTestCase {
    func testMCPStartupLifecycleStaysWiredThroughProtocolTestsAndDocs() throws {
        let root = Self.packageRoot()
        let startup = try text(
            root.appendingPathComponent("Sources/QuillCodeCLI/AppServerMCPStartup.swift")
        )
        let session = try text(
            root.appendingPathComponent("Sources/QuillCodeCLI/AppServerSession.swift")
        )
        let tests = try text(
            root.appendingPathComponent("Tests/QuillCodeCLITests/AppServerMCPTests.swift")
        )
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")

        Self.assertSource(startup, containsAll: [
            "enum AppServerMCPStartupStatus",
            "case starting",
            "case ready",
            "case failed",
            "case cancelled",
            "case reauthenticationRequired",
            "mcpServer/startupStatus/updated",
            "\"failureReason\"",
            "validateRequiredMCPServers",
            "launchOptionalMCPServerStartups",
            "cancelAllMCPServerStartups"
        ])
        Self.assertSource(session, containsAll: [
            "await send(.response(id: id, result: result))",
            "launchOptionalMCPServerStartups(for: mcpStartupThreadToLaunch)"
        ])
        Self.assertSource(tests, containsAll: [
            "testThreadStartEmitsRequiredBeforeResponseAndOptionalAfterResponse",
            "testOptionalMCPFailureEmitsAfterSuccessfulThreadResponse",
            "testMCPStartupNotificationOptOutStillStartsOptionalServers",
            "testReloadCancelsInFlightOptionalMCPStartup",
            "Set([\"threadId\", \"name\", \"status\", \"error\", \"failureReason\"])"
        ])
        Self.assertSource(parity, contains: "mcpServer/startupStatus/updated")
        XCTAssertFalse(
            parity.contains("MCP startup and elicitation notifications"),
            "The parity matrix must not defer the implemented startup lifecycle with elicitation."
        )
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
