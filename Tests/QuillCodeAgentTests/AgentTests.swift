import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentTests: XCTestCase {
    func testRunWhoamiExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("run whoami", in: ChatThread(mode: .auto), workspaceRoot: root)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testBacktickCommandDoesNotBecomeEmptyToolCall() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("Run `pwd`", in: ChatThread(mode: .auto), workspaceRoot: root)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
    }

    func testMakeHelloWorldFileExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send(
            "Can you write a file that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let text = try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8)
        XCTAssertEqual(text, "hello world\n")
        XCTAssertEqual(result.thread.messages.last?.content, "Wrote `hello.txt`.")
    }

    func testApplyPatchRefreshesReviewDiffInSameTurn() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try "old\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git add hello.txt && git commit -m initial", cwd: root)).ok)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let call = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": patch])
        )
        let runner = AgentRunner(llm: FixedToolLLMClient(call: call))

        let result = try await runner.send(
            "apply this patch",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(result.thread.events.map(\.kind), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.git.diff") }.count, 3)
        XCTAssertTrue(result.toolResults[1].stdout.contains("+new"), result.toolResults[1].stdout)
        XCTAssertEqual(result.thread.messages.last?.content, "Patch applied. Review the resulting diff below.")
    }

    func testSendReportsIncrementalToolProgress() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()

        let result = try await AgentRunner().send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root,
            onProgress: { thread in
                await recorder.record(thread)
            }
        )

        XCTAssertTrue(result.toolResults.first?.ok == true)
        let eventKinds = await recorder.eventKinds()
        XCTAssertEqual(eventKinds, [.message, .toolQueued, .toolRunning, .message])
        XCTAssertEqual(
            result.thread.events.map(\.kind),
            [.message, .toolQueued, .toolRunning, .toolCompleted, .message]
        )
    }

    func testStreamingToolActionReportsStatusAndExecutes() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let runner = AgentRunner(llm: StreamingActionLLMClient(chunks: [
            #"{"type":"tool","#,
            #""name":"host.shell.run","#,
            #""arguments":{"cmd":"whoami"}}"#
        ]))

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root,
            onProgress: { thread in
                await recorder.record(thread)
            }
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let eventKinds = await recorder.eventKinds()
        XCTAssertEqual(eventKinds, [.message, .notice, .toolQueued, .toolRunning, .message])
        XCTAssertEqual(result.thread.events.map(\.kind), [
            .message,
            .notice,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
        XCTAssertEqual(result.thread.events[1].summary, AgentRunner.streamingNotice)
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testOpenClawDiscoverySummarizesMissingBinary() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "command -v openclaw || which openclaw || echo 'not found'"
            ])
        )
        let answer = AgentRunner.finalAnswer(for: call, result: ToolResult(ok: true, stdout: "not found\n"))
        XCTAssertEqual(answer, "openclaw is not installed or is not on PATH.")
    }

    func testLongShellOutputIsTruncatedInFinalAnswer() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf long-output"])
        )
        let answer = AgentRunner.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: String(repeating: "x", count: 2_100))
        )
        XCTAssertTrue(answer.contains("[truncated in chat; full output is in the tool card]"))
        XCTAssertLessThan(answer.count, 2_100)
    }

    func testApplyPatchFinalAnswerMentionsDiffRefreshFailure() throws {
        let call = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": "diff --git a/a b/a\n"])
        )

        let answer = AgentRunner.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: "Patch applied.\n"),
            followUpReviewResult: ToolResult(ok: false, stderr: "not a git repository")
        )

        XCTAssertTrue(answer.contains("Patch applied"))
        XCTAssertTrue(answer.contains("could not refresh the review diff"))
        XCTAssertTrue(answer.contains("not a git repository"))
    }

    func testCommitChangesExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)

        let result = try await AgentRunner().send(
            "commit these changes with message Add hello file",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let log = ShellToolExecutor().run(.init(command: "git log -1 --pretty=%s", cwd: root))
        XCTAssertEqual(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Add hello file")
    }

    func testPushCurrentBranchExecutesImmediately() async throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(remote.path)'", cwd: root)).ok)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add hello").ok)

        let result = try await AgentRunner().send(
            "push this branch",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.git.push") }.count, 3)
    }

    func testCreatePullRequestUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "create a pull request titled Add PR tool base main head feature/pr-tool",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestCreate.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["title"], "Add PR tool")
        XCTAssertEqual(arguments["base"], "main")
        XCTAssertEqual(arguments["head"], "feature/pr-tool")
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAgentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func initializeGitRepo(at root: URL) throws {
        let result = ShellToolExecutor().run(.init(
            command: "git init && git config user.email test@example.com && git config user.name QuillCodeTests",
            cwd: root
        ))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }
}

private actor ProgressRecorder {
    private var kinds: [ThreadEventKind] = []

    func record(_ thread: ChatThread) {
        guard let kind = thread.events.last?.kind else { return }
        kinds.append(kind)
    }

    func eventKinds() -> [ThreadEventKind] {
        kinds
    }
}

private struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

private enum StreamingActionLLMError: Error {
    case nonStreamingPathUsed
}

private struct StreamingActionLLMClient: StreamingLLMClient {
    var chunks: [String]

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw StreamingActionLLMError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
