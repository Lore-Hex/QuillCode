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

    func testPermissionAllowExecutesClarifiedCallAndRunsPostHookWithoutApprovalCard() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf allowed"])
        )
        let capture = ToolHookCapture()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Finished.")]),
            safety: AlwaysAskingSafetyReviewer(),
            preToolUseHook: { call, _, _ in
                AgentPreToolUseHookOutcome(call: ToolCall(
                    id: call.id,
                    name: call.name,
                    argumentsJSON: ToolArguments.json(["cmd": "printf permission-rewrite"])
                ))
            },
            postToolUseHook: { call, result, _, _ in
                await capture.recordPost(call, result: result)
                return AgentPostToolUseHookOutcome(result: result)
            },
            permissionRequestHook: { call, reason, _, _ in
                await capture.recordPermission(call, reason: reason)
                return AgentPermissionRequestHookOutcome(
                    decision: .allow,
                    notices: ["Permission hook allowed the command."]
                )
            }
        )

        let result = try await runner.send(
            "Run the command",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )

        XCTAssertNil(result.pendingApproval)
        XCTAssertEqual(result.toolResults.first?.stdout, "permission-rewrite")
        XCTAssertFalse(result.thread.events.contains { $0.kind == .approvalRequested })
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary == "Permission hook allowed the command."
        })
        let counts = await capture.snapshot()
        XCTAssertEqual(counts.permission, 1)
        XCTAssertEqual(counts.post, 1)
        XCTAssertTrue(try XCTUnwrap(counts.permissionInput).contains("permission-rewrite"))
        XCTAssertTrue(try XCTUnwrap(counts.permissionReason).contains("Explicit approval required"))
    }

    func testPermissionDenyReturnsToolFailureWithoutExecutingOrShowingApproval() async throws {
        let root = try makeTempDirectory()
        let target = root.appendingPathComponent("must-not-exist")
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch \(target.path)"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Blocked.")]),
            safety: AlwaysAskingSafetyReviewer(),
            permissionRequestHook: { _, _, _, _ in
                AgentPermissionRequestHookOutcome(decision: .deny(reason: "Denied by trusted policy."))
            }
        )

        let result = try await runner.send(
            "Run it",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertNil(result.pendingApproval)
        XCTAssertEqual(result.toolResults.first?.error, "Denied by trusted policy.")
        XCTAssertFalse(result.thread.events.contains { $0.kind == .approvalRequested })
        XCTAssertFalse(result.thread.events.contains { $0.kind == .toolRunning })
    }

    func testPermissionNoDecisionAndFailurePreserveNormalApproval() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf pending"])
        )
        let hooks: [AgentPermissionRequestHook] = [
            { _, _, _, _ in AgentPermissionRequestHookOutcome() },
            { _, _, _, _ in throw PermissionHookTestError.failed }
        ]
        for hook in hooks {
            let runner = AgentRunner(
                llm: SequenceLLMClient(actions: [.tool(call)]),
                safety: AlwaysAskingSafetyReviewer(),
                permissionRequestHook: hook
            )
            let result = try await runner.send(
                "Run it",
                in: ChatThread(mode: .review),
                workspaceRoot: root
            )

            XCTAssertNotNil(result.pendingApproval)
            XCTAssertEqual(result.thread.events.filter { $0.kind == .approvalRequested }.count, 1)
            XCTAssertFalse(result.thread.events.contains { $0.kind == .toolRunning })
        }
    }

    func testHardSafetyDenyNeverInvokesPermissionHook() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf blocked"])
        )
        let capture = ToolHookCapture()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call)]),
            safety: AlwaysDenyingHookTestSafetyReviewer(),
            permissionRequestHook: { call, reason, _, _ in
                await capture.recordPermission(call, reason: reason)
                return AgentPermissionRequestHookOutcome(decision: .allow)
            }
        )

        let result = try await runner.send(
            "Run it",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertNotNil(result.pendingApproval)
        let counts = await capture.snapshot()
        XCTAssertEqual(counts.permission, 0)
        XCTAssertFalse(result.thread.events.contains { $0.kind == .toolRunning })
    }
}

private actor ToolHookCapture {
    private(set) var preCount = 0
    private(set) var postCount = 0
    private(set) var permissionCount = 0
    private(set) var executedStdout: String?
    private(set) var permissionReason: String?
    private(set) var permissionInput: String?

    func recordPre(_ call: ToolCall) {
        preCount += 1
    }

    func recordPost(_ call: ToolCall, result: ToolResult) {
        postCount += 1
        executedStdout = result.stdout
    }

    func recordPermission(_ call: ToolCall, reason: String) {
        permissionCount += 1
        permissionReason = reason
        permissionInput = call.argumentsJSON
    }

    func snapshot() -> (
        pre: Int,
        post: Int,
        permission: Int,
        stdout: String?,
        permissionReason: String?,
        permissionInput: String?
    ) {
        (preCount, postCount, permissionCount, executedStdout, permissionReason, permissionInput)
    }
}

private struct AlwaysDenyingHookTestSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(verdict: .deny, rationale: "Hard safety denial.")
    }
}

private enum PermissionHookTestError: Error {
    case failed
}
