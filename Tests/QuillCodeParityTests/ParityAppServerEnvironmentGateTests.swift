import XCTest

final class ParityAppServerEnvironmentGateTests: QuillCodeParityTestCase {
    func testExecutionEnvironmentsStayWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let registry = try text(
            root,
            "Sources/QuillCodeCLI/AppServerEnvironmentRegistry.swift"
        )
        let sessionEnvironments = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionEnvironments.swift"
        )
        let connectionClient = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerWebSocketClient.swift"
        )
        let responseRegistry = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerPendingResponseRegistry.swift"
        )
        let fileSystemClient = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerFileSystemClient.swift"
        )
        let processClient = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerProcessClient.swift"
        )
        let sandboxContext = try text(
            root,
            "Sources/QuillCodeCLI/AppServerExecServerSandboxContext.swift"
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
        let processSessionTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerExecServerProcessSessionTests.swift"
        )
        let backgroundTerminalTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerRemoteBackgroundTerminalTests.swift"
        )
        let sandboxTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerExecServerSandboxContextTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-environment-smoke.sh")
        let smokeServer = try text(
            root,
            "scripts/fixtures/app_server_environment_exec_server.py"
        )
        let aggregateSmoke = try text(root, "scripts/smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(session, containsAll: [
            "case \"environment/add\"",
            "case \"environment/info\"",
            "case \"environment/status\"",
            "environmentRegistry"
        ])
        Self.assertSource(registry, containsAll: [
            "Registration acknowledges immediately",
            "func status(",
            "observation.observedAt > subscription.startedAt",
            "unknown environment id",
            "unknown turn environment id",
            "ConnectionEvent",
            "connectionSnapshot",
            "closeAll"
        ])
        Self.assertSource(sessionEnvironments, containsAll: [
            "thread/environment/connected",
            "thread/environment/disconnected",
            "synchronizeEnvironmentSubscription",
            "subscribedThreadIDs.contains(event.threadID)"
        ])
        Self.assertSource(connectionClient, containsAll: [
            "resumeSessionId",
            "method: \"initialize\"",
            "method: \"initialized\"",
            "method: \"environment/status\"",
            "startReader(",
            "readerDidFail(",
            "responseRegistry",
            "catch is CancellationError"
        ])
        Self.assertSource(responseRegistry, containsAll: [
            "abandonedResponseIDs",
            "mutating func abandon(",
            "mutating func take(",
            "received response for unexpected request id"
        ])
        Self.assertSource(fileSystemClient, containsAll: [
            "fs/readFile",
            "fs/writeFile",
            "fs/readDirectory",
            "fs/canonicalize",
            "sandbox.rpcValue"
        ])
        Self.assertSource(processClient, containsAll: [
            "process/start",
            "process/read",
            "process/terminate",
            "request.sandbox.rpcValue",
            "nextSequence - 1",
            "if closed || terminalFailure != nil || sandboxDenied",
            "continuation.yield(.stdout(text))",
            "AppServerRemoteProcessTermination"
        ])
        Self.assertSource(sandboxContext, containsAll: [
            "case managed(entries:",
            "case disabled",
            "case .readOnly:",
            "case .workspaceWrite:",
            "case .dangerFullAccess:",
            "project_roots",
            "workspaceRoots",
            "windowsSandboxPrivateDesktop",
            "useLegacyLandlock"
        ])
        Self.assertSource(executor, containsAll: [
            "remotelyExecutedToolNames",
            "executeUserShell",
            "readFileURIs",
            "canonicalized",
            "AppServerExecServerSandboxContext",
            "sandbox: sandbox"
        ])
        Self.assertSource(userShell, containsAll: [
            "case .disabled:",
            "case .remote(let executor):",
            "environment access is disabled for this thread"
        ])
        Self.assertSource(sessionTests, containsAll: [
            "testEnvironmentStatusUsesCodexCompatibleStatesWithoutUnknownIDError",
            "testSelectedThreadsReceiveFutureConnectionTransitionsWithoutReplay",
            "testSelectedThreadReceivesInitialConnectionFailureWithoutStatusRecovery",
            "testSelectedRemoteEnvironmentRoutesAgentToolAndKeepsContextTransient",
            "testDirectUserShellUsesSelectedRemoteEnvironment",
            "testDirectUserShellRejectsDisabledEnvironmentWithoutDispatch"
        ])
        Self.assertSource(
            transportTests,
            containsAll: [
                "testConcurrentRPCsRouteResponsesAndReconnectResumesSession",
                "testFileSystemRequestsForwardSandboxContext",
                "testStatusProbeUsesExistingConnectionAndIdleClosePublishesFutureTransitions",
                "testProcessReadsAdvanceWithLastObservedSequenceWithoutSkippingOutput"
            ]
        )
        Self.assertSource(processSessionTests, containsAll: [
            "testProcessSessionStreamsBeforeExitAndTerminatesTheStableProcessID",
            "testCancelledProcessReadIgnoresLateReplyWithoutResettingSharedConnection"
        ])
        Self.assertSource(
            backgroundTerminalTests,
            contains: "testRemoteUserShellStreamsListsTerminatesAndCleansThroughUnifiedRegistry"
        )
        Self.assertSource(sandboxTests, containsAll: [
            "testReadOnlyProfileMatchesExecServerProtocol",
            "testWorkspaceWriteProfileProjectsRootsAndExclusionsExactly",
            "testDangerFullAccessUsesDisabledProfileWithoutClaimingManagedEnforcement",
            "testWritableRootForAnotherTargetDriveFailsClosed"
        ])
        Self.assertSource(smoke, containsAll: [
            "import time",
            "environment/status",
            "thread/environment/connected",
            "thread/environment/disconnected",
            "disconnect_client",
            "remote command ran on the local host",
            "disabled command ran locally",
            "late-output",
            "thread/backgroundTerminals/list",
            "remote process terminate was not forwarded",
            "remote background clean was not forwarded",
            "app-server environment smoke passed"
        ])
        Self.assertSource(smokeServer, containsAll: [
            "class ExecServer:",
            "READ_ONLY_SANDBOX",
            "resumeSessionId",
            "environment/status",
            "process/start",
            "process/read",
            "process/terminate",
            "background_processes",
            "process_terminations",
            "send_frame(connection, 8, b\"\")",
            "_wait_for_connection_change",
            "timeout=15",
            "_assert_read_only_sandbox",
            "enforceManagedNetwork",
            "late-output"
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
