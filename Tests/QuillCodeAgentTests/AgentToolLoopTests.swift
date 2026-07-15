import XCTest
import QuillCodeCore
import QuillCodePersistence
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

    func testAgentRunsRequestedSubagentsAndSummarizesTheirResult() async throws {
        let root = try makeTempDirectory()
        let capture = ToolCallCapture()
        let runner = AgentRunner(
            additionalToolDefinitions: [ToolDefinition.subagentsRun],
            threadToolExecutionOverride: { call, _, thread, _ in
                guard call.name == ToolDefinition.subagentsRun.name else { return nil }
                await capture.record(call)
                return AgentThreadToolExecution(
                    thread: thread,
                    result: ToolResult(ok: true, stdout: """
                    {
                      "runID": "D34DB33F-0000-4000-8000-000000000001",
                      "summary": "Subagents completed 2 workers for: Coordinate parallel review of the current task.",
                      "workers": [],
                      "awaitingApproval": false
                    }
                    """)
                )
            }
        )

        let result = try await runner.send(
            "Use two subagents for parallel validation.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "Subagents completed 2 workers for: Coordinate parallel review of the current task."
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.subagentsRun.name) completed"
        })
        let recordedCall = await capture.call
        let capturedCall = try XCTUnwrap(recordedCall)
        let request = try JSONHelpers.decode(
            SubagentRunToolRequest.self,
            from: capturedCall.argumentsJSON
        )
        XCTAssertEqual(request.workers.map { $0.name }, ["Explorer", "Verifier"])
    }

    func testThreadOwningToolMergesStateBeforeTheAgentContinues() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.handoffUpdate.name,
            argumentsJSON: ToolArguments.json(["summary": "Delegated state"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(call),
                .say("Continued with the durable state.")
            ]),
            additionalToolDefinitions: [ToolDefinition.handoffUpdate],
            toolExecutionOverride: { _, _ in
                ToolResult(ok: false, error: "Stateless override should not run.")
            },
            threadToolExecutionOverride: { receivedCall, _, thread, _ in
                guard receivedCall.id == call.id else { return nil }
                var updatedThread = thread
                updatedThread.title = "Thread-owned state"
                return AgentThreadToolExecution(
                    thread: updatedThread,
                    result: ToolResult(ok: true, stdout: "durable result")
                )
            }
        )

        let result = try await runner.send(
            "Run a thread-owning workflow.",
            in: ChatThread(title: "Original"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.title, "Thread-owned state")
        XCTAssertEqual(result.toolResults.first?.stdout, "durable result")
        XCTAssertEqual(result.thread.messages.last?.content, "Continued with the durable state.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "\(ToolDefinition.handoffUpdate.name) completed"
        })
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

    func testAgentLoadsSkillFromInjectedPluginResolver() async throws {
        let root = try makeTempDirectory()
        let skillDirectory = root.appendingPathComponent("plugin-skills/review")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: review
        description: Review code for correctness defects.
        ---

        # Review
        Find correctness defects first.
        """.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let resolver = SkillResolver(roots: [
            SkillRoot(kind: .user, url: root.appendingPathComponent("plugin-skills"))
        ])
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(.init(
                    name: ToolDefinition.skillLoad.name,
                    argumentsJSON: ToolArguments.json(["name": "review"])
                )),
                .say("Loaded the review workflow.")
            ]),
            skillResolver: resolver
        )

        let result = try await runner.send(
            "Use the review skill",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok)
        XCTAssertTrue(result.toolResults[0].stdout.contains("Find correctness defects first."))
        XCTAssertEqual(result.thread.messages.last?.content, "Loaded the review workflow.")
    }

    func testScreenshotAttachmentReachesNextModelStepAsHiddenToolFeedback() async throws {
        let root = try makeTempDirectory()
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("attachments"))
        let screenshot = store.directory
            .appendingPathComponent("computer-use", isDirectory: true)
            .appendingPathComponent("screenshot.png")
        try FileManager.default.createDirectory(
            at: screenshot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try onePixelPNG.write(to: screenshot)
        let state = ScreenshotAwareLLMState()
        let runner = AgentRunner(
            llm: ScreenshotAwareLLMClient(state: state),
            additionalToolDefinitions: [.computerScreenshot],
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.computerScreenshot.name else { return nil }
                return ToolResult(ok: true, stdout: #"{"width":1,"height":1}"#, artifacts: [screenshot.path])
            },
            toolFeedbackAttachmentProvider: { call, result in
                guard call.name == ToolDefinition.computerScreenshot.name,
                      let path = result.artifacts.first,
                      let attachment = try? store.attachmentForManagedImage(
                          at: URL(fileURLWithPath: path)
                      )
                else { return [] }
                return [attachment]
            }
        )

        let result = try await runner.send(
            "Inspect the screen and tell me what you see",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.map(\.role), [.user, .tool, .assistant])
        let feedback = try XCTUnwrap(result.thread.messages.first { $0.role == .tool })
        XCTAssertEqual(feedback.attachments.count, 1)
        XCTAssertEqual(feedback.attachments.first?.localURL, screenshot.standardizedFileURL)
        XCTAssertEqual(result.thread.messages.last?.content, "I inspected the screenshot.")
        let sawScreenshotAttachment = await state.sawScreenshotAttachment
        XCTAssertTrue(sawScreenshotAttachment)
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

    func testAgentRecoversGenericPromisedDiskCheckFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("I'll check your disk usage now."),
            .say("Done after checking disk usage.")
        ]))

        let result = try await runner.send(
            "How much hd is used?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll check")
        })
        let queuedEvent = try XCTUnwrap(result.thread.events.last {
            $0.kind == .toolQueued && $0.payloadJSON != nil
        })
        let call = try JSONHelpers.decode(
            ToolCall.self,
            from: try XCTUnwrap(queuedEvent.payloadJSON)
        )
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(try arguments.requiredString("cmd"), "df -h / /Quill 2>/dev/null || df -h /")
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking disk usage.")
    }

    func testAgentRecoversGenericPromisedFileWriteFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .say("I'll create the file now."),
                .say("Created the file.")
            ]),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "Create a file named notes/hello.txt that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("I'll create")
        })
        let written = try String(
            contentsOf: root.appendingPathComponent("notes/hello.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "hello world\n")
        XCTAssertEqual(result.thread.messages.last?.content, "Created the file.")
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
                "Please handle the setup issue.",
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

    func testAgentRecoversProviderEmptyShellArgumentsFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: EmptyArgumentsThenSayLLMClient(
            finalMessage: "Done after checking disk usage."
        ))

        let result = try await runner.send(
            "How much hd is used?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(try queuedShellCommand(in: result), expectedDiskUsageCommand)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking disk usage.")
    }

    func testAgentRecoversProviderEmptyOpenClawArgumentsFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: EmptyArgumentsThenSayLLMClient(
            finalMessage: "Done after checking OpenClaw."
        ))

        let result = try await runner.send(
            "Do you have openclaw?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(try queuedShellCommand(in: result), expectedOpenClawDiscoveryCommand)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(result.thread.messages.last?.content, "Done after checking OpenClaw.")
    }

    func testAgentRecoversProviderEmptyFileWriteArgumentsFromUserIntent() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(
            llm: EmptyArgumentsThenSayLLMClient(finalMessage: "Created it."),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "Create a file named notes/hello.txt that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let written = try String(
            contentsOf: root.appendingPathComponent("notes/hello.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "hello world\n")
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(result.thread.messages.last?.content, "Created it.")
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

    func testBlockedRunReturnsRawHeldCallAndApprovedContinuationUsesNormalToolPath() async throws {
        let root = try makeTempDirectory()
        let rawCall = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"printf '%s' \"$QUILL_AGENT_SECRET\"","environment":{"QUILL_AGENT_SECRET":"held-secret-value"}}"#
        )
        let runner = AgentRunner(
            llm: FixedToolLLMClient(call: rawCall),
            safety: AlwaysAskingSafetyReviewer()
        )

        let blocked = try await runner.send(
            "run the environment command",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )

        let heldCall = try XCTUnwrap(blocked.pendingApprovalToolCall)
        XCTAssertTrue(heldCall.argumentsJSON.contains("held-secret-value"))
        let approvalPayload = try XCTUnwrap(
            blocked.thread.events.last(where: { $0.kind == .approvalRequested })?.payloadJSON
        )
        XCTAssertFalse(approvalPayload.contains("held-secret-value"))
        XCTAssertTrue(approvalPayload.contains(ToolCall.redactedEnvironmentValue))

        let resumed = try await runner.executeApprovedToolCall(
            heldCall,
            in: blocked.thread,
            workspaceRoot: root
        )

        XCTAssertEqual(resumed.toolResults.first?.stdout, "held-secret-value")
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolQueued }.count, 1)
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolRunning }.count, 1)
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolCompleted }.count, 1)
        XCTAssertEqual(resumed.thread.messages.last?.role, .tool)
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

private struct SubagentRunToolRequest: Decodable {
    struct Worker: Decodable {
        var name: String
    }

    var workers: [Worker]
}

private actor ToolCallCapture {
    private(set) var call: ToolCall?

    func record(_ call: ToolCall) {
        self.call = call
    }
}

private actor ScreenshotAwareLLMState {
    private var callCount = 0
    private(set) var sawScreenshotAttachment = false

    func next(thread: ChatThread) -> AgentAction {
        callCount += 1
        if callCount == 1 {
            return .tool(ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}"))
        }
        sawScreenshotAttachment = thread.messages.contains { message in
            message.role == .tool && !message.attachments.isEmpty
        }
        return .say(sawScreenshotAttachment ? "I inspected the screenshot." : "I could not see the screenshot.")
    }
}

private struct ScreenshotAwareLLMClient: LLMClient {
    let state: ScreenshotAwareLLMState

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        await state.next(thread: thread)
    }
}

private let onePixelPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)!

private struct EmptyArgumentsThenSayLLMClient: LLMClient {
    private let state: EmptyArgumentsThenSayState

    init(finalMessage: String) {
        self.state = EmptyArgumentsThenSayState(finalMessage: finalMessage)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await state.next()
    }
}

private actor EmptyArgumentsThenSayState {
    private var shouldThrow = true
    private let finalMessage: String

    init(finalMessage: String) {
        self.finalMessage = finalMessage
    }

    func next() throws -> AgentAction {
        if shouldThrow {
            shouldThrow = false
            throw TrustedRouterAgentError.emptyToolArguments(ToolDefinition.shellRun.name)
        }
        return .say(finalMessage)
    }
}
