import XCTest

final class ParityAppServerCommandExecGateTests: QuillCodeParityTestCase {
    func testCommandExecStaysWiredThroughRuntimeSandboxTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let management = try text(
            root,
            "Sources/QuillCodeCLI/AppServerCommandExecManagement.swift"
        )
        let models = try text(root, "Sources/QuillCodeCLI/AppServerCommandExecModels.swift")
        let environment = try text(
            root,
            "Sources/QuillCodeCLI/AppServerManagedProcessEnvironment.swift"
        )
        let sandbox = try text(root, "Sources/QuillCodeCLI/AppServerProcessSandbox.swift")
        let tests = try text(root, "Tests/QuillCodeCLITests/AppServerCommandExecTests.swift")
        let processTests = try text(root, "Tests/QuillCodeCLITests/AppServerProcessTests.swift")
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "method == \"command/exec\"",
            "case \"command/exec/write\"",
            "case \"command/exec/resize\"",
            "case \"command/exec/terminate\"",
            "terminateAllCommandExecProcesses"
        ])
        Self.assertSource(management, containsAll: [
            "func startCommandExec",
            "command/exec/outputDelta",
            "func terminateAllCommandExecProcesses",
            "duplicate active command/exec process id",
            "`permissionProfile` cannot be combined with `sandboxPolicy`",
            "AppServerSandboxPolicyParser.parse"
        ])
        Self.assertSource(models, containsAll: [
            "command/exec tty or streaming requires a client-supplied processId",
            "command/exec cannot set both outputBytesCap and disableOutputCap",
            "command/exec cannot set both timeoutMs and disableTimeout"
        ])
        Self.assertSource(environment, containsAll: [
            "AppServerProxyEnvironmentPolicy",
            "allowUpstreamProxy == false",
            "stripUpstreamProxy",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "no_proxy"
        ])
        Self.assertSource(sandbox, containsAll: [
            "/usr/bin/sandbox-exec",
            "bwrap",
            "no supported sandbox runtime is available",
            "filesystemAliases"
        ])
        Self.assertSource(tests, containsAll: [
            "testBufferedExecutionDefersResponseAndAppliesCWDAndEnvironment",
            "testStreamingOutputPrecedesFinalResponseAndIsNotDuplicated",
            "testPTYSupportsInitialSizeResizeAndInteractiveInput",
            "testDuplicateProcessIDIsRejectedThenReusableAfterExit",
            "testDisconnectTerminatesProcessAndSuppressesDeferredResponse",
            "testMacOSSandboxBlocksReadOnlyWritesAndScopesWorkspaceWrites",
            "AppServerSandboxPolicyParser.unsupportedExternalSandboxMessage"
        ])
        Self.assertSource(tests, contains: "testManagedNetworkRequirementsStripUpstreamProxyEnvironment")
        Self.assertSource(
            processTests,
            contains: "testManagedNetworkRequirementsStripUpstreamProxyEnvironmentFromSpawnedProcess"
        )
        Self.assertSource(smoke, containsAll: [
            "command/exec",
            "command/exec/write",
            "command/exec/outputDelta",
            "streamed_command_output == command_payload"
        ])
        Self.assertSource(parity, contains: "App-server standalone command execution")
        Self.assertSource(
            decisions,
            contains: "Standalone app-server commands are connection-owned sandboxed processes"
        )
        Self.assertSource(
            decisions,
            contains: "Managed `allow_upstream_proxy = false` strips proxy environment variables"
        )
        Self.assertSource(research, contains: "experimental `command/exec`")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
