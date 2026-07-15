import Foundation
@testable import QuillCodeCLI
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
import XCTest

final class CLIExecMCPRuntimeTests: XCTestCase {
    func testRequiredServerFailureStopsBeforeModelInvocationOrPersistence() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.required-fixture]
        command = "missing"
        required = true
        """)
        let image = fixture.workspace.appendingPathComponent("attachment.png")
        try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )).write(to: image)
        let llm = CLIExecMCPAgentLLM(expectsMCPTool: false)
        let runnerFactory = CLIExecRunnerFactoryRecorder()
        let output = BufferedCLIOutput()
        var runArguments = arguments(for: fixture, json: true)
        runArguments.insert(contentsOf: ["--image", image.path], at: runArguments.count - 1)
        let status = await commandRunner(
            llm: llm,
            launcher: FakeMCPLauncher(specifications: [:]),
            runnerFactoryRecorder: runnerFactory
        ).run(
            arguments: runArguments,
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        let snapshot = await output.snapshot()
        let records = try jsonLines(snapshot.standardOutput)
        let invocationCount = await llm.invocationCount()
        XCTAssertEqual(status, 1)
        XCTAssertEqual(snapshot.standardError, "")
        XCTAssertEqual(records.compactMap { $0["type"] as? String }, ["error", "turn.failed"])
        XCTAssertTrue(records.description.contains("required MCP servers failed to initialize: required-fixture"))
        XCTAssertEqual(invocationCount, 0)
        XCTAssertEqual(runnerFactory.invocationCount, 0)
        XCTAssertTrue(try threadFiles(in: fixture.home).isEmpty)
        XCTAssertTrue(try attachmentEntries(in: fixture.home).isEmpty)
    }

    func testRequiredFailureTerminatesServersStartedEarlierInDeterministicOrder() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.a-ready]
        command = "ready"

        [mcp_servers.z-required]
        command = "missing"
        required = true
        """)
        let launcher = FakeMCPLauncher(specifications: [
            "ready": FakeMCPServerSpecification(
                probe: Self.toolProbe(serverName: "Ready MCP", toolName: "ping")
            )
        ])
        let output = BufferedCLIOutput()
        let status = await commandRunner(
            llm: CLIExecMCPAgentLLM(expectsMCPTool: false),
            launcher: launcher
        ).run(
            arguments: arguments(for: fixture),
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        let recorder = launcher.recorder(for: "ready")
        XCTAssertEqual(status, 1)
        XCTAssertEqual(recorder.launchCount, 1)
        XCTAssertEqual(recorder.terminationCount, 1)
        XCTAssertTrue(try threadFiles(in: fixture.home).isEmpty)
    }

    func testConfiguredServerToolIsExposedExecutedAndTerminated() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.fixture]
        command = "fixture"
        required = true
        """)
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": FakeMCPServerSpecification(
                probe: Self.toolProbe(serverName: "Fixture MCP", toolName: "ping"),
                toolResult: MCPToolCallResult(
                    content: [.object(["type": .string("text"), "text": .string("pong")])]
                )
            )
        ])
        let llm = CLIExecMCPAgentLLM(expectsMCPTool: true)
        let output = BufferedCLIOutput()
        let status = await commandRunner(llm: llm, launcher: launcher).run(
            arguments: arguments(for: fixture),
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        let snapshot = await output.snapshot()
        let recorder = launcher.recorder(for: "fixture")
        let observedTools = await llm.observedMCPTools()
        XCTAssertEqual(status, 0)
        XCTAssertTrue(snapshot.standardOutput.contains("MCP tool completed."))
        XCTAssertEqual(observedTools.first, ["mcp__fixture__ping"])
        XCTAssertEqual(recorder.probeDetails, [.toolsAndAuthOnly])
        XCTAssertEqual(recorder.toolCalls.map(\.tool), ["ping"])
        XCTAssertEqual(recorder.launchCount, 1)
        XCTAssertEqual(recorder.terminationCount, 1)
    }

    func testOptionalServerFailureDoesNotBlockExec() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.optional-fixture]
        command = "missing"
        """)
        let llm = CLIExecMCPAgentLLM(expectsMCPTool: false)
        let output = BufferedCLIOutput()
        let status = await commandRunner(
            llm: llm,
            launcher: FakeMCPLauncher(specifications: [:])
        ).run(
            arguments: arguments(for: fixture),
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        let observedTools = await llm.observedMCPTools()
        XCTAssertEqual(status, 0)
        XCTAssertEqual(observedTools, [[]])
        XCTAssertEqual(try threadFiles(in: fixture.home).count, 1)
    }

    func testIgnoreUserConfigSkipsRequiredMCPConfiguration() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.required-fixture]
        command = "missing"
        required = true
        """)
        let llm = CLIExecMCPAgentLLM(expectsMCPTool: false)
        let output = BufferedCLIOutput()
        var runArguments = arguments(for: fixture)
        runArguments.insert("--ignore-user-config", at: runArguments.count - 1)
        let status = await commandRunner(
            llm: llm,
            launcher: FakeMCPLauncher(specifications: [:])
        ).run(
            arguments: runArguments,
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        let invocationCount = await llm.invocationCount()
        XCTAssertEqual(status, 0)
        XCTAssertEqual(invocationCount, 1)
    }

    func testProjectConfigurationOverridesGlobalServerForExec() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.fixture]
        command = "global"
        required = true
        """)
        let projectConfig = fixture.workspace.appendingPathComponent(".quillcode/config.toml")
        try FileManager.default.createDirectory(
            at: projectConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        [mcp_servers.fixture]
        command = "project"
        required = true
        """.utf8).write(to: projectConfig)
        let launcher = FakeMCPLauncher(specifications: [
            "global": .init(probe: Self.toolProbe(serverName: "Global MCP", toolName: "ping")),
            "project": .init(probe: Self.toolProbe(serverName: "Project MCP", toolName: "ping"))
        ])
        let output = BufferedCLIOutput()
        let status = await commandRunner(
            llm: CLIExecMCPAgentLLM(expectsMCPTool: true),
            launcher: launcher
        ).run(
            arguments: arguments(for: fixture),
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        XCTAssertEqual(status, 0)
        XCTAssertEqual(launcher.recorder(for: "global").launchCount, 0)
        XCTAssertEqual(launcher.recorder(for: "project").launchCount, 1)
        XCTAssertEqual(launcher.recorder(for: "project").toolCalls.map(\.tool), ["ping"])
        XCTAssertEqual(launcher.recorder(for: "project").terminationCount, 1)
    }

    func testResumeLoadsCurrentMCPConfiguration() async throws {
        let fixture = try makeFixture(config: "")
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.toolProbe(serverName: "Fixture MCP", toolName: "ping"))
        ])
        let firstStatus = await commandRunner(
            llm: CLIExecMCPAgentLLM(expectsMCPTool: false),
            launcher: launcher
        ).run(
            arguments: arguments(for: fixture),
            input: BufferedCLIInput(isTerminal: true),
            output: BufferedCLIOutput()
        )
        XCTAssertEqual(firstStatus, 0)

        try Data("""
        [mcp_servers.fixture]
        command = "fixture"
        required = true
        """.utf8).write(to: fixture.home.appendingPathComponent("config.toml"))
        let resumeStatus = await commandRunner(
            llm: CLIExecMCPAgentLLM(expectsMCPTool: true),
            launcher: launcher
        ).run(
            arguments: [
                "--home", fixture.home.path,
                "exec", "resume", "--last", "--mock", "--skip-git-repo-check",
                "--cwd", fixture.workspace.path, "use the newly configured MCP server"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: BufferedCLIOutput()
        )

        XCTAssertEqual(resumeStatus, 0)
        XCTAssertEqual(launcher.recorder(for: "fixture").toolCalls.map(\.tool), ["ping"])
        XCTAssertEqual(try threadFiles(in: fixture.home).count, 1)
    }

    func testPreparedServerTerminatesWhenRunnerFactoryThrows() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.fixture]
        command = "fixture"
        required = true
        """)
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.toolProbe(serverName: "Fixture MCP", toolName: "ping"))
        ])
        let runner = QuillCodeCommandRunner(
            parser: CLIArgumentParser(),
            runnerFactory: { _ in throw CLIExecMCPTestError.runnerFactoryFailed },
            interruptSource: InactiveCLIInterruptSource(),
            mcpSessionPreparer: CLIMCPAgentSessionPreparer(launcher: launcher)
        )
        let output = BufferedCLIOutput()
        let status = await runner.run(
            arguments: arguments(for: fixture),
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )

        let snapshot = await output.snapshot()
        XCTAssertEqual(status, 1)
        XCTAssertTrue(snapshot.standardError.contains("runner factory failed"))
        XCTAssertEqual(launcher.recorder(for: "fixture").terminationCount, 1)
        XCTAssertTrue(try threadFiles(in: fixture.home).isEmpty)
    }

    func testInterruptTerminatesPreparedServer() async throws {
        let fixture = try makeFixture(config: """
        [mcp_servers.fixture]
        command = "fixture"
        required = true
        """)
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.toolProbe(serverName: "Fixture MCP", toolName: "ping"))
        ])
        let llm = CLIExecBlockingLLM()
        let interruptSource = CLIExecManualInterruptSource()
        let output = BufferedCLIOutput()
        let runner = commandRunner(
            llm: llm,
            launcher: launcher,
            interruptSource: interruptSource
        )
        let runArguments = arguments(for: fixture, json: true)
        let run = Task {
            await runner.run(
                arguments: runArguments,
                input: BufferedCLIInput(isTerminal: true),
                output: output
            )
        }
        await llm.waitUntilStarted()
        interruptSource.interrupt()

        let status = await run.value
        XCTAssertEqual(status, 1)
        XCTAssertEqual(launcher.recorder(for: "fixture").terminationCount, 1)
        let eventTypes = try jsonLines((await output.snapshot()).standardOutput)
            .compactMap { $0["type"] as? String }
        XCTAssertFalse(eventTypes.contains("turn.completed"))
    }

    private func commandRunner(
        llm: any LLMClient,
        launcher: any MCPClientLaunching,
        interruptSource: any CLIInterruptSource = InactiveCLIInterruptSource(),
        runnerFactoryRecorder: CLIExecRunnerFactoryRecorder? = nil
    ) -> QuillCodeCommandRunner {
        QuillCodeCommandRunner(
            parser: CLIArgumentParser(),
            runnerFactory: { configuration in
                runnerFactoryRecorder?.recordInvocation()
                return AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: true
                )
            },
            interruptSource: interruptSource,
            mcpSessionPreparer: CLIMCPAgentSessionPreparer(launcher: launcher)
        )
    }

    private func arguments(for fixture: Fixture, json: Bool = false) -> [String] {
        var result = [
            "--home", fixture.home.path,
            "exec", "--mock", "--skip-git-repo-check", "--cwd", fixture.workspace.path
        ]
        if json { result.append("--json") }
        result.append("use the configured MCP server")
        return result
    }

    private func makeFixture(config: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-cli-mcp-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data(config.utf8).write(to: home.appendingPathComponent("config.toml"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(home: home, workspace: workspace)
    }

    private func threadFiles(in home: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: home.appendingPathComponent("threads", isDirectory: true),
            includingPropertiesForKeys: nil
        )
    }

    private func attachmentEntries(in home: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: home.appendingPathComponent("attachments", isDirectory: true),
            includingPropertiesForKeys: nil
        )
    }

    private func jsonLines(_ output: String) throws -> [[String: Any]] {
        try output.split(whereSeparator: \.isNewline).map { line in
            let value = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(value as? [String: Any])
        }
    }

    private static func toolProbe(serverName: String, toolName: String) -> MCPServerProbeResult {
        MCPServerProbeResult(
            protocolVersion: "2025-03-26",
            serverName: serverName,
            tools: [
                .object([
                    "name": .string(toolName),
                    "inputSchema": .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    "annotations": .object(["readOnlyHint": .bool(true)])
                ])
            ],
            toolNames: [toolName]
        )
    }
}

private extension CLIExecMCPRuntimeTests {
    struct Fixture {
        var home: URL
        var workspace: URL
    }
}

private actor CLIExecMCPAgentLLM: LLMClient {
    private let expectsMCPTool: Bool
    private var observed: [[String]] = []

    init(expectsMCPTool: Bool) {
        self.expectsMCPTool = expectsMCPTool
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        _ = userMessage
        let mcpTools = tools.filter { $0.host == .mcp }.map(\.name).sorted()
        observed.append(mcpTools)
        guard expectsMCPTool, thread.messages.last?.role != .tool else {
            return .say(expectsMCPTool ? "MCP tool completed." : "No MCP tool required.")
        }
        guard let tool = mcpTools.first else {
            throw MCPProbeError.responseError("No MCP tool was available to the exec model.")
        }
        return .tool(ToolCall(name: tool, argumentsJSON: "{}"))
    }

    func invocationCount() -> Int { observed.count }
    func observedMCPTools() -> [[String]] { observed }
}

private enum CLIExecMCPTestError: LocalizedError {
    case runnerFactoryFailed

    var errorDescription: String? { "runner factory failed" }
}

private actor CLIExecBlockingLLM: LLMClient {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        _ = (thread, userMessage, tools)
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("Unexpected completion.")
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class CLIExecManualInterruptSource: CLIInterruptSource, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func makeInterruptStream() -> AsyncStream<Void> { stream }

    func interrupt() {
        continuation.yield()
        continuation.finish()
    }
}

private final class CLIExecRunnerFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInvocationCount = 0

    var invocationCount: Int {
        lock.withLock { storedInvocationCount }
    }

    func recordInvocation() {
        lock.withLock { storedInvocationCount += 1 }
    }
}
