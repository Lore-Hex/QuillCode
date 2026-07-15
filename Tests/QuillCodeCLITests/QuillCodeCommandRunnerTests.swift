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

    func testSkipGitCheckWorksAndDangerousSandboxFailsClosed() async throws {
        let workspace = try temporaryDirectory(prefix: "unguarded-workspace")
        let home = try temporaryDirectory(prefix: "sandbox-home")
        let runner = commandRunner(llm: EchoLLM())
        let allowedOutput = BufferedCLIOutput()
        let allowedStatus = await runner.run(
            arguments: [
                "--home", home.path, "exec", "--mock", "--skip-git-repo-check",
                "--cwd", workspace.path, "inspect"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: allowedOutput
        )
        XCTAssertEqual(allowedStatus, 0)

        let deniedOutput = BufferedCLIOutput()
        let deniedStatus = await runner.run(
            arguments: [
                "--home", home.path, "exec", "--mock", "--skip-git-repo-check",
                "--sandbox", "danger-full-access", "--cwd", workspace.path, "inspect"
            ],
            input: BufferedCLIInput(isTerminal: true),
            output: deniedOutput
        )
        let deniedSnapshot = await deniedOutput.snapshot()
        XCTAssertEqual(deniedStatus, 1)
        XCTAssertTrue(deniedSnapshot.standardError.contains("refused to claim broader access"))
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

    private func commandRunner(llm: any LLMClient) -> QuillCodeCommandRunner {
        QuillCodeCommandRunner(runnerFactory: { configuration in
            AgentRunner(
                llm: llm,
                safety: StaticSafetyReviewer(),
                maxToolSteps: configuration.appConfig.maxToolSteps,
                enablesImmediateActionPreflight: true
            )
        })
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
