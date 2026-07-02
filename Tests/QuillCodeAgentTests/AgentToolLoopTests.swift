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

    func testAgentUsesSubagentProgressToolWhenAvailable() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.subagentsUpdate],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.subagentsUpdate.name else { return nil }
                return ToolResult(ok: true, stdout: call.argumentsJSON)
            }
        )

        let result = try await runner.send(
            "show subagent progress for parallel agent validation",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(result.thread.messages.last?.content, "Updated subagent progress.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.subagentsUpdate.name) completed"
        })
        let update = try JSONHelpers.decode(SubagentProgressUpdate.self, from: result.toolResults[0].stdout)
        XCTAssertEqual(update.subagents.map(\.name), ["Explorer", "Verifier"])
        XCTAssertEqual(update.subagents.map(\.status), [.completed, .running])
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

    func testExplicitUserCommandedFileWriteCanOverwriteExistingFileInOneTurn() async throws {
        let root = try makeTempDirectory()
        try "old\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        var runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("The provider should not be needed for this explicit preflight write.")
        ]))
        runner.enablesImmediateActionPreflight = true

        let result = try await runner.send(
            "write a file at notes.txt that says new",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8), "new\n")
    }

    func testModelAuthoredFileWriteToUnreadExistingFileIsBlocked() async throws {
        let root = try makeTempDirectory()
        try "old\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(.init(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "notes.txt",
                        "content": "new\n"
                    ])
                )),
                .say("The write was refused because I need to read the file first.")
            ]),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "change notes",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertFalse(result.toolResults[0].ok)
        XCTAssertTrue(result.toolResults[0].error?.contains("not read in this session") == true)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8), "old\n")
    }

    func testAgentRecoversBacktickedPromisedWorkAnswerBeforeFinalizing() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll run `whoami` on the device."),
            .say("Done after running whoami.")
        ]))

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll run")
        })
        XCTAssertFalse(result.toolResults[0].stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after running whoami.")
    }

    func testAgentRecoversNonBacktickedPromisedWorkAnswerBeforeFinalizing() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll run whoami on the device."),
            .say("Done after running whoami.")
        ]))

        let result = try await runner.send(
            "whoami?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll run")
        })
        XCTAssertFalse(result.toolResults[0].stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after running whoami.")
    }

    func testAgentRecoversComplexBacktickedPromisedShellAnswerBeforeFinalizing() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .say("I'll execute `command -v definitely_missing_quillcode_binary || echo not found`."),
                .say("Done after checking the command.")
            ]),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "Do you have definitely_missing_quillcode_binary?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll execute")
        })
        XCTAssertEqual(result.toolResults[0].stdout.trimmingCharacters(in: .whitespacesAndNewlines), "not found")
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking the command.")
    }

    func testAgentDoesNotFinalizeRepeatedPromisedWorkAnswers() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll check the disk usage now."),
            .say("I'll check the disk usage now."),
            .say("I'll check the disk usage now.")
        ]))

        do {
            _ = try await runner.send(
                "How much disk is used?",
                in: ChatThread(mode: .auto),
                workspaceRoot: root
            )
            XCTFail("Expected repeated promised work to throw.")
        } catch AgentError.promisedWorkWithoutToolAction {
            // Expected: do not leak another fake final answer into the transcript.
        } catch {
            XCTFail("Expected promisedWorkWithoutToolAction, got \(error).")
        }
    }

    func testAgentDoesNotRetryInformationalAnswerThatMentionsCapabilities() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I can run commands, edit files, and review diffs when you ask.")
        ]))

        let result = try await runner.send(
            "what can you do?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "I can run commands, edit files, and review diffs when you ask."
        )
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
        // The agent's tool loop refuses to patch an existing file the THREAD's session never
        // read — record the fixture file as read in this thread's edit session.
        let thread = ChatThread(mode: .auto)
        FileEditSessionGuard.session(for: thread.id).markRead(root.appendingPathComponent("hello.txt"))
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
            in: thread,
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
