import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentToolUseHookTests: XCTestCase {
    func testPreRewriteRunsBeforeExecutionAndPostFeedbackReachesModel() async throws {
        let root = try makeTempDirectory()
        let original = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )
        let capture = ToolHookCapture()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(original), .say("Finished.")]),
            safety: AlwaysApprovingSafetyReviewer(),
            preToolUseHook: { call, _, _ in
                await capture.recordPre(call)
                return AgentPreToolUseHookOutcome(
                    call: ToolCall(
                        id: call.id,
                        name: call.name,
                        argumentsJSON: ToolArguments.json(["cmd": "printf rewritten"])
                    ),
                    additionalContexts: ["private pre context"],
                    notices: ["pre warning"]
                )
            },
            postToolUseHook: { call, result, _, _ in
                await capture.recordPost(call, result: result)
                var replacement = result
                replacement.stdout = "post feedback"
                return AgentPostToolUseHookOutcome(
                    result: replacement,
                    additionalContexts: ["private post context"],
                    notices: ["post warning"]
                )
            }
        )

        let result = try await runner.send(
            "Run the command",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "post feedback")
        let counts = await capture.snapshot()
        XCTAssertEqual(counts.pre, 1)
        XCTAssertEqual(counts.post, 1)
        XCTAssertEqual(counts.stdout, "rewritten")
        let queued = try XCTUnwrap(result.thread.events.first { $0.kind == .toolQueued }?.payloadJSON)
        XCTAssertTrue(queued.contains("printf rewritten"))
        XCTAssertEqual(
            result.thread.messages.filter { $0.role == .system }.map(\.content),
            ["private pre context", "private post context"]
        )
        XCTAssertEqual(
            result.thread.events.filter { $0.kind == .notice }.map(\.summary),
            ["pre warning", "post warning"]
        )
    }

    func testApprovalResumeDoesNotRepeatPreHookAndStillRunsPostHook() async throws {
        let root = try makeTempDirectory()
        let original = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )
        let capture = ToolHookCapture()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(original), .say("Approved.")]),
            safety: AlwaysAskingSafetyReviewer(),
            preToolUseHook: { call, _, _ in
                await capture.recordPre(call)
                return AgentPreToolUseHookOutcome(call: ToolCall(
                    id: call.id,
                    name: call.name,
                    argumentsJSON: ToolArguments.json(["cmd": "printf approved-rewrite"])
                ))
            },
            postToolUseHook: { call, result, _, _ in
                await capture.recordPost(call, result: result)
                return AgentPostToolUseHookOutcome(result: result)
            }
        )

        let paused = try await runner.send(
            "Run the command",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )
        let pending = try XCTUnwrap(paused.pendingApproval)
        XCTAssertTrue(try XCTUnwrap(pending.heldToolCall).argumentsJSON.contains("approved-rewrite"))
        var counts = await capture.snapshot()
        XCTAssertEqual(counts.pre, 1)
        XCTAssertEqual(counts.post, 0)

        let resumed = try await runner.resumeApproved(
            pending,
            in: paused.thread,
            workspaceRoot: root,
            userMessage: "Run the command"
        )

        XCTAssertNil(resumed.pendingApproval)
        counts = await capture.snapshot()
        XCTAssertEqual(counts.pre, 1)
        XCTAssertEqual(counts.post, 1)
        XCTAssertEqual(counts.stdout, "approved-rewrite")
    }

    func testPreHookDenialNeverExecutesTheTool() async throws {
        let root = try makeTempDirectory()
        let target = root.appendingPathComponent("must-not-exist")
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch \(target.path)"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Blocked.")]),
            safety: AlwaysApprovingSafetyReviewer(),
            preToolUseHook: { call, _, _ in
                AgentPreToolUseHookOutcome(call: call, blockedReason: "Policy hook denied this command.")
            }
        )

        let result = try await runner.send(
            "Run it",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(result.toolResults.first?.error, "Policy hook denied this command.")
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolRunning }.count, 0)
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolFailed }.count, 1)
    }

    func testPreHookCannotSwapToolIdentityAfterDefinitionSelection() async throws {
        let root = try makeTempDirectory()
        let original = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(original), .say("Finished.")]),
            safety: AlwaysApprovingSafetyReviewer(),
            preToolUseHook: { _, _, _ in
                AgentPreToolUseHookOutcome(call: ToolCall(
                    id: "swapped-id",
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json(["path": "wrong.txt", "content": "wrong"])
                ))
            }
        )

        let result = try await runner.send(
            "Run the command",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("wrong.txt").path))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("changed the tool identity")
        })
    }
}

private actor ToolHookCapture {
    private(set) var preCount = 0
    private(set) var postCount = 0
    private(set) var executedStdout: String?

    func recordPre(_ call: ToolCall) {
        preCount += 1
    }

    func recordPost(_ call: ToolCall, result: ToolResult) {
        postCount += 1
        executedStdout = result.stdout
    }

    func snapshot() -> (pre: Int, post: Int, stdout: String?) {
        (preCount, postCount, executedStdout)
    }
}
