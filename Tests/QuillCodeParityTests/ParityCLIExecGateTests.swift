import XCTest

final class ParityCLIExecGateTests: QuillCodeParityTestCase {
    func testNonInteractiveExecContractStaysWiredThroughRuntimeTestsAndSmoke() throws {
        let root = Self.packageRoot()
        let package = try text(root.appendingPathComponent("Package.swift"))
        let parser = try text(root.appendingPathComponent("Sources/QuillCodeCLI/CLIArgumentParser.swift"))
        let runner = try text(root.appendingPathComponent("Sources/QuillCodeCLI/QuillCodeCommandRunner.swift"))
        let mcpSession = try text(root.appendingPathComponent("Sources/QuillCodeCLI/CLIMCPAgentSession.swift"))
        let mcpAdapter = try text(root.appendingPathComponent("Sources/QuillCodeCLI/MCPAgentRunnerAdapter.swift"))
        let reporter = try text(root.appendingPathComponent("Sources/QuillCodeCLI/CLIProgressReporter.swift"))
        let interrupts = try text(root.appendingPathComponent("Sources/QuillCodeCLI/CLIInterruptSource.swift"))
        let tests = try text(
            root.appendingPathComponent("Tests/QuillCodeCLITests/QuillCodeCommandRunnerTests.swift")
        )
        let mcpTests = try text(
            root.appendingPathComponent("Tests/QuillCodeCLITests/CLIExecMCPRuntimeTests.swift")
        )
        let smoke = try text(root.appendingPathComponent("scripts/cli-exec-smoke.sh"))
        let aggregateSmoke = try text(root.appendingPathComponent("scripts/smoke.sh"))
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")

        Self.assertSource(package, containsAll: [
            ".library(name: \"QuillCodeCLI\"",
            ".testTarget(\n            name: \"QuillCodeCLITests\""
        ])
        Self.assertSource(parser, containsAll: [
            "tokens.first == \"resume\"",
            "case \"--json\"",
            "case \"--ephemeral\"",
            "case \"--output-schema\"",
            "case \"--skip-git-repo-check\""
        ])
        Self.assertSource(runner, containsAll: [
            "CLIRepositoryGuard().validate",
            "CLIPromptResolver().resolve",
            "mcpSessionPreparer.prepare",
            "schema?.validate(finalMessage:",
            "CLIRunPersistence"
        ])
        Self.assertSource(mcpSession, containsAll: [
            "CLIMCPAgentSessionPreparer",
            "AppServerMCPConfigurationLoader.load",
            "MCPAgentRunnerAdapter.prepare",
            "terminateAll"
        ])
        Self.assertSource(mcpAdapter, containsAll: [
            "agentToolCatalog",
            "executeAgentTool",
            "inheritedExecution?(call, workspaceRoot)"
        ])
        Self.assertSource(interrupts, containsAll: [
            "ProcessCLIInterruptSource",
            "DispatchSource.makeSignalSource",
            "runUntilInterrupted"
        ])
        Self.assertSource(reporter, containsAll: [
            "thread.started",
            "turn.started",
            "item.completed",
            "turn.completed",
            "turn.failed"
        ])
        Self.assertSource(tests, containsAll: [
            "testJSONExecEmitsMachineReadableLifecycleWithoutPlainFinalText",
            "testExactResumeEmitsOnlyNewAssistantMessage",
            "testJSONFailureLifecycleNeverClaimsTurnCompleted",
            "testInterruptCancelsRunPersistsPartialThreadAndDoesNotWriteFinalOutput",
            "testSkipGitCheckWorksAndDangerousSandboxFailsClosed"
        ])
        Self.assertSource(mcpTests, containsAll: [
            "testRequiredServerFailureStopsBeforeModelInvocationOrPersistence",
            "testRequiredFailureTerminatesServersStartedEarlierInDeterministicOrder",
            "testConfiguredServerToolIsExposedExecutedAndTerminated",
            "testOptionalServerFailureDoesNotBlockExec",
            "testIgnoreUserConfigSkipsRequiredMCPConfiguration",
            "testProjectConfigurationOverridesGlobalServerForExec",
            "testResumeLoadsCurrentMCPConfiguration",
            "testPreparedServerTerminatesWhenRunnerFactoryThrows",
            "testInterruptTerminatesPreparedServer"
        ])
        Self.assertSource(smoke, containsAll: [
            "exec --mock --json --ephemeral",
            "exec resume --last",
            "not inside a Git repository",
            "kill -INT",
            "Stopped by user",
            "required MCP startup and process cleanup",
            "QUILLCODE_MCP_PID_FILE",
            "scripts/fixtures/mcp-stdio-server.py",
            "required MCP servers failed to initialize"
        ])
        Self.assertSource(aggregateSmoke, contains: "scripts/cli-exec-smoke.sh")
        Self.assertSource(parity, contains: "| CLI | Non-interactive exec | Partial |")
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
