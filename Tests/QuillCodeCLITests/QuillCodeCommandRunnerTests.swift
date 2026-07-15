import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class QuillCodeCommandRunnerTests: XCTestCase {
    func testPlainExecKeepsProgressOnStderrAndFinalMessageOnStdout() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "home")
        let output = BufferedCLIOutput()
        let runner = commandRunner(llm: ScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "printf quill-cli"])
            )),
            .say("Command completed.")
        ]))

        let status = await runner.run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--sandbox", "workspace-write",
                "--cwd", workspace.path,
                "run printf quill-cli"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        let snapshot = await output.snapshot()
        XCTAssertEqual(status, 0)
        XCTAssertTrue(snapshot.standardOutput.contains("quill-cli"))
        XCTAssertTrue(snapshot.standardError.contains("Thread "))
        XCTAssertTrue(snapshot.standardError.contains("→ host.shell.run"))
        XCTAssertTrue(snapshot.standardError.contains("✓ host.shell.run"))
        XCTAssertEqual(try JSONThreadStore(directory: home.appendingPathComponent("threads")).list().count, 1)
    }

    func testJSONExecEmitsMachineReadableLifecycleWithoutPlainFinalText() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "json-home")
        let output = BufferedCLIOutput()
        let runner = commandRunner(llm: ScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "printf json-event"])
            )),
            .say("JSON run done.")
        ]))
        let status = await runner.run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--json", "--sandbox", "workspace-write",
                "--cwd", workspace.path,
                "run printf json-event"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        let snapshot = await output.snapshot()
        XCTAssertEqual(status, 0)
        XCTAssertEqual(snapshot.standardError, "")
        let records = try jsonLines(snapshot.standardOutput)
        let types = records.compactMap { $0["type"] as? String }
        XCTAssertEqual(types.first, "thread.started")
        XCTAssertTrue(types.contains("turn.started"))
        XCTAssertTrue(types.contains("item.started"))
        XCTAssertTrue(types.contains("item.completed"))
        XCTAssertEqual(types.last, "turn.completed")
        XCTAssertFalse(snapshot.standardOutput.contains("\nJSON run done.\n"))
    }

    func testEphemeralRunDoesNotPersistThread() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "ephemeral-home")
        let output = BufferedCLIOutput()
        let status = await commandRunner(llm: ScriptedLLM(actions: [.say("Transient.")])).run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--ephemeral", "--cwd", workspace.path, "inspect"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        XCTAssertEqual(status, 0)
        XCTAssertEqual(
            try JSONThreadStore(directory: home.appendingPathComponent("threads")).list(),
            []
        )
    }

    func testResumeLastContinuesSameThread() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "resume-home")
        let firstOutput = BufferedCLIOutput()
        let commandRunner = commandRunner(llm: EchoLLM())
        let firstStatus = await commandRunner.run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--cwd", workspace.path, "first"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: firstOutput
        )
        XCTAssertEqual(firstStatus, 0)

        let secondOutput = BufferedCLIOutput()
        let secondStatus = await commandRunner.run(
            arguments: [
                "--home", home.path,
                "exec", "resume", "--last", "--mock", "--cwd", workspace.path, "second"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: secondOutput
        )
        XCTAssertEqual(secondStatus, 0)

        let threads = try JSONThreadStore(directory: home.appendingPathComponent("threads")).list()
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].messages.filter { $0.role == .user }.map(\.content), ["first", "second"])
    }

    func testOutputSchemaValidatesAndWritesLastMessage() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "schema-home")
        let schema = home.appendingPathComponent("schema.json")
        let final = home.appendingPathComponent("final.json")
        try """
        {"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}
        """.write(to: schema, atomically: true, encoding: .utf8)
        let output = BufferedCLIOutput()
        let status = await commandRunner(llm: ScriptedLLM(actions: [.say("{\"ok\":true}")])).run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--cwd", workspace.path,
                "--output-schema", schema.path,
                "--output-last-message", final.path,
                "return status"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        XCTAssertEqual(status, 0)
        XCTAssertEqual(try String(contentsOf: final, encoding: .utf8), "{\"ok\":true}")
    }

    func testSchemaMismatchAndRepositoryGuardFailClosed() async throws {
        let workspace = try temporaryDirectory(prefix: "not-git")
        let home = try temporaryDirectory(prefix: "failure-home")
        let schema = home.appendingPathComponent("schema.json")
        try "{\"type\":\"object\"}".write(to: schema, atomically: true, encoding: .utf8)
        let output = BufferedCLIOutput()
        let runner = commandRunner(llm: ScriptedLLM(actions: [.say("not json")]))

        let repositoryStatus = await runner.run(
            arguments: ["--home", home.path, "exec", "--mock", "--cwd", workspace.path, "inspect"],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        let repositoryOutput = await output.snapshot()
        XCTAssertEqual(repositoryStatus, 1)
        XCTAssertTrue(repositoryOutput.standardError.contains("not inside a Git repository"))

        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        let schemaOutput = BufferedCLIOutput()
        let schemaStatus = await runner.run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--cwd", workspace.path,
                "--output-schema", schema.path,
                "inspect"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: schemaOutput
        )
        let schemaSnapshot = await schemaOutput.snapshot()
        XCTAssertEqual(schemaStatus, 1)
        XCTAssertTrue(schemaSnapshot.standardError.contains("does not match --output-schema"))
    }

    func testStdinContextAndDeprecatedFullAutoWarningReachRun() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "stdin-home")
        let output = BufferedCLIOutput()
        let status = await commandRunner(llm: EchoLLM()).run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--full-auto", "--cwd", workspace.path, "summarize"
            ],
            input: BufferedCLIInput(text: "piped log", isTerminal: false),
            output: output
        )
        let snapshot = await output.snapshot()
        XCTAssertEqual(status, 0)
        XCTAssertTrue(snapshot.standardOutput.contains("<cli_stdin_context>"))
        XCTAssertTrue(snapshot.standardOutput.contains("piped log"))
        XCTAssertTrue(snapshot.standardError.contains("--full-auto is deprecated"))
    }

    func testJSONFailureLifecycleNeverClaimsTurnCompleted() async throws {
        let workspace = try temporaryDirectory(prefix: "json-failure-workspace")
        let home = try temporaryDirectory(prefix: "json-failure-home")
        let output = BufferedCLIOutput()
        let status = await commandRunner(llm: EchoLLM()).run(
            arguments: [
                "--home", home.path,
                "exec", "--mock", "--json", "--cwd", workspace.path, "inspect"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: output
        )
        let snapshot = await output.snapshot()
        let types = try jsonLines(snapshot.standardOutput).compactMap { $0["type"] as? String }
        XCTAssertEqual(status, 1)
        XCTAssertEqual(snapshot.standardError, "")
        XCTAssertEqual(types, ["error", "turn.failed"])
        XCTAssertFalse(types.contains("turn.completed"))
    }

    func testInterruptCancelsRunPersistsPartialThreadAndDoesNotWriteFinalOutput() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "interrupt-home")
        let finalOutput = home.appendingPathComponent("final.txt")
        let output = BufferedCLIOutput()
        let llm = BlockingLLM()
        let interruptSource = ManualCLIInterruptSource()
        let runner = commandRunner(llm: llm, interruptSource: interruptSource)

        let run = Task {
            await runner.run(
                arguments: [
                    "--home", home.path,
                    "exec", "--mock", "--json", "--cwd", workspace.path,
                    "--output-last-message", finalOutput.path,
                    "wait for interruption"
                ],
                input: BufferedCLIInput(isTerminal: true),
                output: output
            )
        }
        await llm.waitUntilStarted()
        interruptSource.interrupt()

        let status = await run.value
        let snapshot = await output.snapshot()
        let records = try jsonLines(snapshot.standardOutput)
        let types = records.compactMap { $0["type"] as? String }
        let thread = try XCTUnwrap(
            JSONThreadStore(directory: home.appendingPathComponent("threads")).list().first
        )

        XCTAssertEqual(status, 1)
        XCTAssertEqual(snapshot.standardError, "")
        XCTAssertEqual(types.prefix(2), ["thread.started", "turn.started"])
        XCTAssertFalse(types.contains("error"))
        XCTAssertFalse(types.contains("turn.failed"))
        XCTAssertFalse(types.contains("turn.completed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalOutput.path))
        XCTAssertTrue(thread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testExactResumeEmitsOnlyNewAssistantMessage() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "exact-resume-home")
        let firstOutput = BufferedCLIOutput()
        let runner = commandRunner(llm: EchoLLM())
        let firstStatus = await runner.run(
            arguments: ["--home", home.path, "exec", "--mock", "--cwd", workspace.path, "first"],
            input: BufferedCLIInput(isTerminal: true),
            output: firstOutput
        )
        XCTAssertEqual(firstStatus, 0)
        let original = try XCTUnwrap(
            JSONThreadStore(directory: home.appendingPathComponent("threads")).list().first
        )

        let resumeOutput = BufferedCLIOutput()
        let resumeStatus = await runner.run(
            arguments: [
                "--home", home.path, "exec", "resume", original.id.uuidString,
                "--mock", "--json", "--cwd", workspace.path, "second"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: resumeOutput
        )
        let records = try jsonLines((await resumeOutput.snapshot()).standardOutput)
        let completedAgentMessages = records.filter { record in
            record["type"] as? String == "item.completed"
                && (record["item"] as? [String: Any])?["type"] as? String == "agent_message"
        }
        XCTAssertEqual(resumeStatus, 0)
        XCTAssertEqual(records.first?["thread_id"] as? String, original.id.uuidString.lowercased())
        XCTAssertEqual(completedAgentMessages.count, 1)
    }

    func testAppServerCommandDrainsStdioTurnBeforeExiting() async throws {
        let workspace = try temporaryDirectory(prefix: "app-server-workspace")
        let home = try temporaryDirectory(prefix: "app-server-home")
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let thread = ChatThread(id: UUID(), mode: .readOnly, model: "trustedrouter/fast")
        try JSONThreadStore(directory: paths.threadsDirectory).save(thread)
        let input = """
        {"id":1,"method":"initialize","params":{"clientInfo":{"name":"stdio-test","version":"1"}}}
        {"method":"initialized","params":{}}
        {"id":2,"method":"turn/start","params":{"threadId":"\(thread.id.uuidString.lowercased())","input":[{"type":"text","text":"hello over stdio"}]}}

        """
        let output = BufferedCLIOutput()
        let status = await commandRunner(llm: EchoLLM()).run(
            arguments: ["--home", home.path, "app-server", "--mock"],
            currentDirectory: workspace,
            input: BufferedCLIInput(text: input, isTerminal: false),
            output: output
        )

        let snapshot = await output.snapshot()
        let records = try jsonLines(snapshot.standardOutput)
        XCTAssertEqual(status, 0)
        XCTAssertEqual(snapshot.standardError, "")
        XCTAssertNotNil(records.first { ($0["id"] as? Int) == 1 }?["result"])
        XCTAssertNotNil(records.first { ($0["id"] as? Int) == 2 }?["result"])
        XCTAssertTrue(records.contains { $0["method"] as? String == "turn/completed" })
        let stored = try JSONThreadStore(directory: paths.threadsDirectory).load(thread.id)
        XCTAssertEqual(stored.messages.filter { $0.role == .user }.map(\.content), ["hello over stdio"])
        XCTAssertEqual(stored.messages.filter { $0.role == .assistant }.map(\.content), ["hello over stdio"])
    }

    func testSkipGitCheckAndDangerFullAccessReadOutsideWorkspace() async throws {
        let workspace = try temporaryDirectory(prefix: "unguarded-workspace")
        let home = try temporaryDirectory(prefix: "sandbox-home")
        let outside = try temporaryDirectory(prefix: "sandbox-outside")
        let externalFile = outside.appendingPathComponent("external.txt")
        try "full-access-proof\n".write(to: externalFile, atomically: true, encoding: .utf8)
        let runner = commandRunner(llm: ScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": externalFile.path])
            )),
            .say("External file inspected.")
        ]))
        let allowedOutput = BufferedCLIOutput()
        let allowedStatus = await runner.run(
            arguments: [
                "--home", home.path, "exec", "--mock", "--skip-git-repo-check",
                "--sandbox", "danger-full-access", "--cwd", workspace.path,
                "read the external file"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: allowedOutput
        )
        XCTAssertEqual(allowedStatus, 0)
        let stored = try XCTUnwrap(JSONThreadStore(
            directory: home.appendingPathComponent("threads")
        ).list().first)
        XCTAssertTrue(stored.messages.contains { message in
            message.role == .tool && message.content.contains("full-access-proof")
        })
    }

    func testAuthCommandsNeverEchoStoredSecret() async throws {
        let home = try temporaryDirectory(prefix: "auth-home")
        let secret = "sk-test-private-value"
        let output = BufferedCLIOutput()
        let runner = commandRunner(llm: EchoLLM())
        let setStatus = await runner.run(
            arguments: ["--home", home.path, "auth", "set-key", secret],
            output: output
        )
        let statusStatus = await runner.run(
            arguments: ["--home", home.path, "auth", "status"],
            output: output
        )
        let snapshot = await output.snapshot()
        XCTAssertEqual(setStatus, 0)
        XCTAssertEqual(statusStatus, 0)
        XCTAssertFalse(snapshot.standardOutput.contains(secret))
        XCTAssertFalse(snapshot.standardError.contains(secret))
        XCTAssertTrue(snapshot.standardOutput.contains("key configured"))
    }

    func testInvalidStdinAndMissingOutputParentFailCleanly() async throws {
        let workspace = try gitWorkspace()
        let home = try temporaryDirectory(prefix: "io-failure-home")
        let runner = commandRunner(llm: EchoLLM())
        let stdinOutput = BufferedCLIOutput()
        let stdinStatus = await runner.run(
            arguments: ["--home", home.path, "exec", "--mock", "--cwd", workspace.path, "-"],
            input: BufferedCLIInput(data: Data([0xFF]), isTerminal: false),
            output: stdinOutput
        )
        let stdinSnapshot = await stdinOutput.snapshot()
        XCTAssertEqual(stdinStatus, 1)
        XCTAssertTrue(stdinSnapshot.standardError.contains("valid UTF-8"))

        let fileOutput = BufferedCLIOutput()
        let fileStatus = await runner.run(
            arguments: [
                "--home", home.path, "exec", "--mock", "--cwd", workspace.path,
                "-o", home.appendingPathComponent("missing/final.txt").path, "inspect"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: fileOutput
        )
        let fileSnapshot = await fileOutput.snapshot()
        XCTAssertEqual(fileStatus, 1)
        XCTAssertTrue(fileSnapshot.standardError.contains("doesn’t exist")
            || fileSnapshot.standardError.contains("does not exist")
            || fileSnapshot.standardError.contains("No such file"))
    }

    func testDoctorHelpDispatchesWithoutCreatingState() async throws {
        let root = try temporaryDirectory(prefix: "doctor-help")
        let home = root.appendingPathComponent("missing-home", isDirectory: true)
        let output = BufferedCLIOutput()

        let status = await commandRunner(llm: EchoLLM()).run(
            arguments: ["--home", home.path, "doctor", "--help"],
            input: BufferedCLIInput(isTerminal: false),
            output: output
        )
        let snapshot = await output.snapshot()

        XCTAssertEqual(status, 0)
        XCTAssertTrue(snapshot.standardOutput.contains("Usage: quill-code [--home PATH] doctor"))
        XCTAssertEqual(snapshot.standardError, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }

    private func commandRunner(
        llm: any LLMClient,
        interruptSource: any CLIInterruptSource = InactiveCLIInterruptSource()
    ) -> QuillCodeCommandRunner {
        QuillCodeCommandRunner(
            parser: CLIArgumentParser(),
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: true
                )
            },
            interruptSource: interruptSource
        )
    }

    private func gitWorkspace() throws -> URL {
        let root = try temporaryDirectory(prefix: "workspace")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        return root
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-cli-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func jsonLines(_ text: String) throws -> [[String: Any]] {
        try text.split(separator: "\n").map { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(object as? [String: Any])
        }
    }
}

private actor ScriptedLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        guard !actions.isEmpty else { return .say("No scripted action remains.") }
        return actions.removeFirst()
    }
}

private struct EchoLLM: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor BlockingLLM: LLMClient {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("Unexpected completion.")
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private final class ManualCLIInterruptSource: CLIInterruptSource, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func makeInterruptStream() -> AsyncStream<Void> {
        stream
    }

    func interrupt() {
        continuation.yield()
        continuation.finish()
    }
}
