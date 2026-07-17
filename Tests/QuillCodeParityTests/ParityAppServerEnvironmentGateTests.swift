import XCTest

final class ParityAppServerEnvironmentGateTests: QuillCodeParityTestCase {
    func testExecutionEnvironmentsStayWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let registry = try text(
            root,
            "Sources/QuillCodeCLI/AppServerEnvironmentRegistry.swift"
        )
        let connectionClient = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerWebSocketClient.swift"
        )
        let fileSystemClient = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerFileSystemClient.swift"
        )
        let processClient = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerProcessClient.swift"
        )
        let executor = try text(
            root,
            "Sources/QuillCodeCLI/AppServerRemoteEnvironmentToolExecutor.swift"
        )
        let userShell = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionUserShell.swift"
        )
        let sessionTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerEnvironmentSessionTests.swift"
        )
        let transportTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerExecServerWebSocketClientTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-environment-smoke.sh")
        let aggregateSmoke = try text(root, "scripts/smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(session, containsAll: [
            "case \"environment/add\"",
            "case \"environment/info\"",
            "environmentRegistry"
        ])
        Self.assertSource(registry, containsAll: [
            "Registration is intentionally lazy",
            "unknown environment id",
            "unknown turn environment id",
            "closeAll"
        ])
        Self.assertSource(connectionClient, containsAll: [
            "resumeSessionId",
            "method: \"initialize\"",
            "method: \"initialized\""
        ])
        Self.assertSource(fileSystemClient, containsAll: [
            "fs/readFile",
            "fs/writeFile",
            "fs/readDirectory",
            "fs/canonicalize"
        ])
        Self.assertSource(processClient, containsAll: [
            "process/start",
            "process/read",
            "nextSequence - 1",
            "if closed || terminalFailure != nil || sandboxDenied",
            "withTaskCancellationHandler"
        ])
        Self.assertSource(executor, containsAll: [
            "remotelyExecutedToolNames",
            "executeUserShell",
            "readFileURIs",
            "canonicalized"
        ])
        Self.assertSource(userShell, containsAll: [
            "case .disabled:",
            "case .remote(let executor):",
            "environment access is disabled for this thread"
        ])
        Self.assertSource(sessionTests, containsAll: [
            "testSelectedRemoteEnvironmentRoutesAgentToolAndKeepsContextTransient",
            "testDirectUserShellUsesSelectedRemoteEnvironment",
            "testDirectUserShellRejectsDisabledEnvironmentWithoutDispatch"
        ])
        Self.assertSource(
            transportTests,
            containsAll: [
                "testConcurrentRPCsAreSerializedAndReconnectResumesSession",
                "testProcessReadsAdvanceWithLastObservedSequenceWithoutSkippingOutput"
            ]
        )
        Self.assertSource(smoke, containsAll: [
            "remote command ran on the local host",
            "disabled command ran locally",
            "late-output",
            "app-server environment smoke passed"
        ])
        Self.assertSource(aggregateSmoke, contains: "app-server-environment-smoke.sh")
        Self.assertSource(parity, contains: "App-server execution environments")
        Self.assertSource(research, contains: "exec-server WebSocket")
        Self.assertSource(
            decisions,
            contains: "App-server execution environments fail closed across every host path"
        )
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
