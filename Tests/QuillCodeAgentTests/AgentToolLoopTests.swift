import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentToolLoopTests: XCTestCase {
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

    func testAgentUsesHandoffUpdateToolWhenAvailable() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.handoffUpdate],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.handoffUpdate.name else { return nil }
                return ToolResult(ok: true, stdout: call.argumentsJSON)
            }
        )

        let result = try await runner.send(
            "write a handoff summary",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(result.thread.messages.last?.content, "Updated the handoff summary.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.handoffUpdate.name) completed"
        })
        let update = try JSONHelpers.decode(AgentHandoffUpdate.self, from: result.toolResults[0].stdout)
        XCTAssertEqual(update.summary, "Current task state is ready for continuation.")
        XCTAssertEqual(update.nextSteps, ["Review the latest tool output", "Continue from the Activity pane"])
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
}
