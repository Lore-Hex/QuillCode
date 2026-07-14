import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectRunHookSemanticsIntegrationTests: XCTestCase {
    func testUserPromptContextReachesModelAndWarningIsSurfaced() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let hook = fixture.hook(
            timing: .beforeAgentRun,
            command: #"printf '%s' '{"systemMessage":"Policy loaded","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Use the release branch."}}'"#
        )
        let session = fixture.session(
            prompt: "continue",
            hooks: [hook],
            llm: HookContextCheckingLLM()
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .system, .assistant])
        XCTAssertEqual(result.thread.messages.last?.content, "context received")
        XCTAssertTrue(result.thread.messages[1].content.contains("Use the release branch."))
        XCTAssertEqual(
            WorkspaceTranscriptSurfaceBuilder(thread: result.thread).messageSurfaces().map(\.text),
            ["continue", "context received"]
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Hook warning") && $0.summary.contains("Policy loaded")
        })
    }

    func testUserPromptBlockPreventsModelCallAndExitTwoIsCompletedSemantically() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let calls = HookLLMCallCounter()
        let hook = fixture.hook(
            timing: .beforeAgentRun,
            command: "printf 'Ticket is required.' >&2; exit 2"
        )
        let session = fixture.session(
            prompt: "continue",
            hooks: [hook],
            llm: CountingHookLLM(counter: calls)
        )

        let result = try await session.run()

        let callCount = await calls.value
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(result.thread.messages.last?.content.contains("Ticket is required.") == true)
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolCompleted }.count, 1)
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolFailed }.count, 0)
    }

    func testStopBlockRunsOneContinuationAndSetsActiveFlag() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let command = #"payload=$(cat); printf '%s\n' "$payload" >> stop-inputs.jsonl; case "$payload" in *'"stop_hook_active":false'*) printf '%s' '{"decision":"block","reason":"Run verification."}' ;; *) printf '%s' '{}' ;; esac"#
        let hook = fixture.hook(timing: .afterAgentRun, command: command)
        let session = fixture.session(
            prompt: "implement",
            hooks: [hook],
            llm: HookActionSequenceLLM(actions: [.say("first answer"), .say("verified answer")])
        )

        let result = try await session.run()

        XCTAssertEqual(
            result.thread.messages.filter { $0.role != .system }.map(\.content),
            ["implement", "first answer", "Run verification.", "verified answer"]
        )
        let payloads = try String(
            contentsOf: fixture.root.appendingPathComponent("stop-inputs.jsonl"),
            encoding: .utf8
        ).split(separator: "\n")
        XCTAssertEqual(payloads.count, 2)
        XCTAssertTrue(payloads[0].contains(#""stop_hook_active":false"#))
        XCTAssertTrue(payloads[1].contains(#""stop_hook_active":true"#))
        XCTAssertEqual(
            result.thread.events.filter { $0.summary == "Stop hook requested another agent turn" }.count,
            1
        )
    }

    func testStopContinueFalseOverridesAnotherContinuationRequest() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let hooks = [
            fixture.hook(
                id: "first",
                timing: .afterAgentRun,
                command: #"printf '%s' '{"decision":"block","reason":"Keep working."}'"#
            ),
            fixture.hook(
                id: "second",
                timing: .afterAgentRun,
                command: #"printf '%s' '{"continue":false,"stopReason":"Stop now."}'"#
            )
        ]
        let calls = HookLLMCallCounter()
        let session = fixture.session(
            prompt: "implement",
            hooks: hooks,
            llm: CountingHookLLM(counter: calls)
        )

        let result = try await session.run()

        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(result.thread.messages.contains { $0.content == "Keep working." })
        XCTAssertTrue(result.thread.events.contains { $0.summary == "Stop hook ended the run: Stop now." })
    }

    func testMalformedStopOutputKeepsAnswerAndReportsHookFailure() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let hook = fixture.hook(timing: .afterAgentRun, command: "printf 'not json'")
        let session = fixture.session(
            prompt: "implement",
            hooks: [hook],
            llm: HookActionSequenceLLM(actions: [.say("answer")])
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages[1].content, "answer")
        XCTAssertTrue(result.thread.messages.last?.content.contains("Stop hook output must be a JSON object") == true)
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolFailed }.count, 1)
    }

    func testStopContinuationCannotLoopMoreThanOnce() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let hook = fixture.hook(
            timing: .afterAgentRun,
            command: #"cat >/dev/null; printf '%s' '{"decision":"block","reason":"Keep going."}'"#
        )
        let calls = HookLLMCallCounter()
        let session = fixture.session(
            prompt: "implement",
            hooks: [hook],
            llm: CountingHookLLM(counter: calls)
        )

        let result = try await session.run()

        let callCount = await calls.value
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.thread.messages.filter { $0.role == .user }.map(\.content), ["implement", "Keep going."])
        XCTAssertTrue(result.thread.events.contains {
            $0.summary == "Ignored another Stop-hook continuation from Demo hook."
        })
    }

    func testStopContinuationSurvivesApprovalPauseAndResume() async throws {
        let fixture = try PluginHookFixture(root: makeQuillCodeTestDirectory())
        let command = #"payload=$(cat); printf '%s\n' "$payload" >> approval-stop-inputs.jsonl; case "$payload" in *'"stop_hook_active":false'*) printf '%s' '{"decision":"block","reason":"Write verification marker."}' ;; *) printf '%s' '{}' ;; esac"#
        let hook = fixture.hook(timing: .afterAgentRun, command: command)
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "verified.txt", "content": "done"])
        )
        let llm = HookActionSequenceLLM(actions: [
            .say("first answer"),
            .tool(write),
            .say("verified answer")
        ])
        let thread = ChatThread(title: "Hooks", mode: .review)
        let runner = AgentRunner(llm: llm, safety: StaticSafetyReviewer())
        let session = WorkspaceAgentSendSession(
            prompt: "implement",
            thread: thread,
            runner: runner,
            workspaceRoot: fixture.root,
            runHooks: [hook],
            pluginDataBaseDirectory: fixture.pluginData
        )

        let paused = try await session.run()
        let pending = try XCTUnwrap(paused.pendingApproval)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("verified.txt").path
        ))

        let resumed = try await WorkspaceAgentSendSession(
            prompt: "implement",
            thread: paused.thread,
            runner: runner,
            workspaceRoot: fixture.root,
            recordsUserMessage: false,
            runHooks: [hook],
            pluginDataBaseDirectory: fixture.pluginData
        ).resumeApproved(pending)

        XCTAssertNil(resumed.pendingApproval)
        XCTAssertEqual(
            resumed.thread.messages.filter { $0.role == .user }.map(\.content),
            ["implement", "Write verification marker."]
        )
        XCTAssertEqual(resumed.thread.messages.last?.content, "verified answer")
        XCTAssertEqual(
            try String(
                contentsOf: fixture.root.appendingPathComponent("verified.txt"),
                encoding: .utf8
            ),
            "done"
        )
        let payloads = try String(
            contentsOf: fixture.root.appendingPathComponent("approval-stop-inputs.jsonl"),
            encoding: .utf8
        ).split(separator: "\n")
        XCTAssertEqual(payloads.count, 2)
        XCTAssertTrue(payloads[0].contains(#""stop_hook_active":false"#))
        XCTAssertTrue(payloads[1].contains(#""stop_hook_active":true"#))
    }
}

private struct PluginHookFixture {
    let root: URL
    let pluginData: URL

    init(root: URL) throws {
        self.root = root
        pluginData = root.appendingPathComponent("private-plugin-data", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func hook(
        id: String = UUID().uuidString,
        timing: ProjectRunHookTiming,
        command: String
    ) -> ProjectRunHook {
        ProjectRunHook(
            id: id,
            timing: timing,
            title: "Demo hook",
            relativePath: ".quillcode/plugins/demo/hooks.json",
            command: command,
            pluginID: "plugin:demo",
            pluginRootRelativePath: ".quillcode/plugins/demo"
        )
    }

    func session(
        prompt: String,
        hooks: [ProjectRunHook],
        llm: any LLMClient
    ) -> WorkspaceAgentSendSession {
        WorkspaceAgentSendSession(
            prompt: prompt,
            thread: ChatThread(title: "Hooks"),
            runner: AgentRunner(llm: llm),
            workspaceRoot: root,
            runHooks: hooks,
            pluginDataBaseDirectory: pluginData
        )
    }
}

private struct HookContextCheckingLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        let received = thread.messages.contains {
            $0.role == .system && $0.content.contains("Use the release branch.")
        }
        return .say(received ? "context received" : "context missing")
    }
}

private actor HookLLMCallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct CountingHookLLM: LLMClient {
    let counter: HookLLMCallCounter

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        await counter.increment()
        return .say("answer")
    }
}

private actor HookActionSequenceState {
    var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next() -> AgentAction {
        actions.isEmpty ? .say("done") : actions.removeFirst()
    }
}

private struct HookActionSequenceLLM: LLMClient {
    let state: HookActionSequenceState

    init(actions: [AgentAction]) {
        state = HookActionSequenceState(actions: actions)
    }

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        await state.next()
    }
}
