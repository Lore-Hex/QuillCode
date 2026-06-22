import XCTest
import QuillCodeCore
import QuillCodeSafety
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

    func testAgentUsesPlanUpdateToolWhenAvailable() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.planUpdate],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.planUpdate.name else { return nil }
                return ToolResult(ok: true, stdout: call.argumentsJSON)
            }
        )

        let result = try await runner.send(
            "plan the work",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(result.thread.messages.last?.content, "Updated the task plan.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.planUpdate.name) completed"
        })
        let update = try JSONHelpers.decode(AgentPlanUpdate.self, from: result.toolResults[0].stdout)
        XCTAssertEqual(update.plan.map(\.status), [.completed, .inProgress, .pending])
    }

    func testAgentContinuesAcrossMultipleToolCallsInOneTurn() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "hello.txt",
                    "content": "hello world\n"
                ])
            )),
            .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "cat hello.txt"])
            )),
            .say("Created `hello.txt` and verified its contents.")
        ]))

        let result = try await runner.send(
            "write hello world to a file and verify it",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8),
            "hello world\n"
        )
        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .tool, .tool, .assistant])
        XCTAssertEqual(result.thread.messages.last?.content, "Created `hello.txt` and verified its contents.")
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
    }

    func testRepeatedToolCallFallsBackToSynthesizedFinalAnswer() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let runner = AgentRunner(llm: FixedToolLLMClient(call: call))

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.shell.run") }.count, 3)
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testAgentRedactsEnvironmentValuesInQueuedToolEventButExecutesRawValues() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"printf '%s' \"$QUILL_AGENT_SECRET\"","environment":{"QUILL_AGENT_SECRET":"agent-secret-value"}}"#
        )
        let runner = AgentRunner(
            llm: FixedToolLLMClient(call: call),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "run the environment command",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "agent-secret-value")
        let queued = try XCTUnwrap(result.thread.events.first { $0.kind == .toolQueued })
        let payload = try XCTUnwrap(queued.payloadJSON)
        XCTAssertTrue(payload.contains("QUILL_AGENT_SECRET"))
        XCTAssertTrue(payload.contains(ToolCall.redactedEnvironmentValue))
        XCTAssertFalse(payload.contains("agent-secret-value"))
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
        XCTAssertEqual(eventKinds, [.message, .notice, .toolQueued, .toolRunning, .notice, .message])
        XCTAssertEqual(result.thread.events.map(\.kind), [
            .message,
            .notice,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .notice,
            .message
        ])
        XCTAssertEqual(result.thread.events[1].summary, AgentRunner.streamingNotice)
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testStreamingSayActionPublishesDraftAndFinalizesWithoutDuplicateMessage() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let runner = AgentRunner(llm: StreamingActionLLMClient(chunks: [
            #"{"type":"say","text":"hello"#,
            #" world"}"#
        ]))

        let result = try await runner.send(
            "say hello",
            in: ChatThread(mode: .auto),
            workspaceRoot: root,
            onProgress: { thread in
                await recorder.record(thread)
            }
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(result.thread.messages.last?.content, "hello world")
        XCTAssertEqual(result.thread.events.map(\.kind), [.message, .notice, .message])
        XCTAssertEqual(result.thread.events.last?.summary, "hello world")
        let progressMessages = await recorder.messageContents()
        XCTAssertTrue(progressMessages.contains(["say hello", "hello"]))
        XCTAssertTrue(progressMessages.contains(["say hello", "hello world"]))
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

    func testBrowserInspectFinalAnswerSummarizesPage() throws {
        let output = BrowserInspectionToolOutput(
            url: "http://localhost:5173",
            title: "Preview Page",
            status: "Preview ready",
            sourceLabel: "Local web app",
            inspectionDepth: .metadataOnly,
            summary: "Live DOM capture is not attached yet; QuillCode has URL metadata for this local page.",
            details: ["Host: localhost", "Scheme: HTTP", "Path: /"],
            outline: ["Page: localhost", "Path: /", "H1: Hero Preview"],
            textSnippet: "Hero Preview Buy now",
            comments: [
                .init(
                    url: "http://localhost:5173",
                    text: "Check the hero spacing",
                    createdAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )
        let call = ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}")

        let answer = AgentRunner.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(output))
        )

        XCTAssertTrue(answer.contains("Inspected `Preview Page` at http://localhost:5173."))
        XCTAssertTrue(answer.contains("Inspection depth: Metadata only."))
        XCTAssertTrue(answer.contains("Outline: Page: localhost; Path: /; H1: Hero Preview."))
        XCTAssertTrue(answer.contains("Text: Hero Preview Buy now"))
        XCTAssertTrue(answer.contains("Browser comments: Check the hero spacing."))
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

    func testViewPullRequestUsesReadOnlyToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "show current PR comments",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(call.argumentsJSON, "{}")
    }

    func testPullRequestChecksUsesReadOnlyToolCallWithSelector() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "check PR #42 status",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestChecks.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
    }

    func testPullRequestCheckoutUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "checkout PR #42",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestCheckout.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
    }

    func testPullRequestReviewerRequestUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "request review from alice and myorg/team-name on PR #42",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReviewers.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["add"], "alice,myorg/team-name")
    }

    func testPullRequestLabelRequestUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "label PR #42 merge-train",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestLabels.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["add"], "merge-train")
    }

    func testPullRequestCommentUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "comment on PR #42 saying Ready for review",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestComment.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["body"], "Ready for review")
    }

    func testPullRequestReviewUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "request changes on PR #42 saying Please add tests",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReview.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["action"], "request_changes")
        XCTAssertEqual(arguments["body"], "Please add tests")
    }

    func testPullRequestMergeUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "auto merge PR #42 with rebase and delete branch",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestMerge.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["method"], "rebase")
        XCTAssertEqual(arguments["auto"], "true")
        XCTAssertEqual(arguments["deleteBranch"], "true")
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
    private var contents: [[String]] = []

    func record(_ thread: ChatThread) {
        guard let kind = thread.events.last?.kind else { return }
        kinds.append(kind)
        contents.append(thread.messages.map(\.content))
    }

    func eventKinds() -> [ThreadEventKind] {
        kinds
    }

    func messageContents() -> [[String]] {
        contents
    }
}

private struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

private struct AlwaysApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(verdict: .approve, rationale: "Approved for transcript redaction test.")
    }
}

private actor SequenceLLMState {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next() -> AgentAction {
        guard !actions.isEmpty else {
            return .say("Done.")
        }
        return actions.removeFirst()
    }
}

private struct SequenceLLMClient: LLMClient {
    private let state: SequenceLLMState

    init(actions: [AgentAction]) {
        self.state = SequenceLLMState(actions: actions)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        await state.next()
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
