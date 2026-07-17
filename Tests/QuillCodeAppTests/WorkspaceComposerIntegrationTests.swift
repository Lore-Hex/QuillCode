import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

@MainActor
final class WorkspaceComposerIntegrationTests: XCTestCase {
    func testSubmitComposerRunsToolAndBuildsToolCard() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertFalse(model.composer.isSending)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.hasPrefix("You are `") == true)

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, ToolDefinition.shellRun.name)
        XCTAssertEqual(cards[0].status, .done)
        XCTAssertTrue(cards[0].inputJSON?.contains("whoami") == true)
        XCTAssertTrue(cards[0].outputJSON?.contains("\"ok\" : true") == true)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user, .tool, .assistant])
        XCTAssertEqual(WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces().map(\.role), [.user, .assistant])
        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()
        XCTAssertEqual(timeline.map(\.kind), [.message, .toolCard, .message])
        XCTAssertEqual(timeline[0].message?.role, .user)
        XCTAssertEqual(timeline[1].toolCard?.title, ToolDefinition.shellRun.name)
        XCTAssertEqual(timeline[2].message?.role, .assistant)
    }

    func testSubmitComposerSurfacesToolArtifacts() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.fileWrite.name)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.label), ["hello.txt"])
        XCTAssertEqual(card.artifacts.map(\.kind), [.file])
        XCTAssertEqual(card.artifacts.map(\.detail), [root.path])
        XCTAssertEqual(card.artifacts.first?.value, root.appendingPathComponent("hello.txt").path)
        XCTAssertEqual(card.artifacts.first?.textPreview, "hello world\n")
        XCTAssertEqual(card.textPreviewArtifacts.map(\.label), ["hello.txt"])
    }

    func testInlineSideConversationRunsOneTurnWithoutMutatingParentTranscript() async throws {
        let workspaceRoot = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("Explain the main implementation")
        await model.submitComposer(workspaceRoot: workspaceRoot)
        let parent = try XCTUnwrap(model.selectedThread)
        let parentMessages = parent.messages

        model.setDraft("/side run whoami")
        await model.submitComposer(workspaceRoot: workspaceRoot)

        let side = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(side.runtimeContext.sideConversationParentThreadID, parent.id)
        XCTAssertEqual(Array(side.messages.prefix(parentMessages.count)), parentMessages)
        XCTAssertEqual(side.messages[parentMessages.count].role, .user)
        XCTAssertEqual(side.messages[parentMessages.count].content, "run whoami")
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.shellRun.name)
        XCTAssertTrue(model.currentToolCards.last?.inputJSON?.contains("whoami") == true)
        XCTAssertEqual(model.root.threads.first { $0.id == parent.id }?.messages, parentMessages)
        XCTAssertEqual(model.root.sidebarItems.map(\.id), [parent.id])

        XCTAssertTrue(model.returnFromSideConversation())
        XCTAssertEqual(model.selectedThread?.id, parent.id)
        XCTAssertEqual(model.selectedThread?.messages, parentMessages)
    }

    func testWorkspaceSurfaceCoversRealWorldActionPromptFamily() async throws {
        let root = try makeTempDirectory()
        let downloadSource = root.appendingPathComponent("source.html")
        try "<!doctype html><title>QuillCode surface smoke</title>\n"
            .write(to: downloadSource, atomically: true, encoding: .utf8)

        let cases = [
            RealWorldSurfaceCase(
                prompt: "whoami?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["\"cmd\":\"whoami\""],
                answerContains: "You are `",
                sideEffect: nil
            ),
            RealWorldSurfaceCase(
                prompt: "How much hd?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["df -h / /Quill"],
                answerContains: "Disk usage:",
                sideEffect: nil
            ),
            RealWorldSurfaceCase(
                prompt: "Do you have openclaw?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["command -v openclaw"],
                answerContains: "openclaw is",
                sideEffect: nil
            ),
            RealWorldSurfaceCase(
                prompt: "Can you write a file that says \"hello world\"",
                toolName: ToolDefinition.fileWrite.name,
                inputContains: ["\"path\":\"hello.txt\"", "hello world"],
                answerContains: "Wrote `hello.txt`.",
                sideEffect: .fileContains(path: "hello.txt", text: "hello world")
            ),
            RealWorldSurfaceCase(
                prompt: "Download \(downloadSource.absoluteString) into `downloads/example.html` in this workspace.",
                toolName: ToolDefinition.shellRun.name,
                inputContains: [
                    "mkdir -p 'downloads'",
                    "--output 'downloads/example.html'",
                    downloadSource.absoluteString
                ],
                answerContains: "Downloaded to `downloads/example.html`.",
                sideEffect: .fileContains(path: "downloads/example.html", text: "QuillCode surface smoke")
            )
        ]

        for testCase in cases {
            let model = QuillCodeWorkspaceModel()
            model.setDraft(testCase.prompt)
            await model.submitComposer(workspaceRoot: root)

            let surface = model.surface()
            XCTAssertFalse(model.composer.isSending, testCase.prompt)
            XCTAssertNil(model.lastError, testCase.prompt)
            XCTAssertEqual(surface.transcript.timelineItems.map(\.kind), [.message, .toolCard, .message], testCase.prompt)
            XCTAssertEqual(surface.transcript.messages.first?.text, testCase.prompt)
            XCTAssertEqual(surface.transcript.toolCards.count, 1, testCase.prompt)

            let card = try XCTUnwrap(surface.transcript.toolCards.first, testCase.prompt)
            XCTAssertEqual(card.title, testCase.toolName, testCase.prompt)
            XCTAssertEqual(card.status, .done, testCase.prompt)
            XCTAssertNotEqual(card.inputJSON, "{}", testCase.prompt)
            let normalizedInputJSON = normalizeToolInputJSON(card.inputJSON)
            for expectedInput in testCase.inputContains {
                let normalizedExpectedInput = expectedInput.replacingOccurrences(of: " ", with: "")
                XCTAssertTrue(
                    normalizedInputJSON.contains(normalizedExpectedInput),
                    "\(testCase.prompt): \(expectedInput)"
                )
            }

            let answer = try XCTUnwrap(surface.transcript.messages.last?.text, testCase.prompt)
            XCTAssertTrue(answer.contains(testCase.answerContains), "\(testCase.prompt): \(answer)")
            XCTAssertFalse(answer.range(of: #"I'?ll (run|check|do|download|create|write)"#, options: .regularExpression) != nil, testCase.prompt)
            XCTAssertFalse(answer.localizedCaseInsensitiveContains("No shell command was specified"), testCase.prompt)

            try assertSideEffect(testCase.sideEffect, workspaceRoot: root, label: testCase.prompt)
        }
    }

    func testSubmitComposerDispatchesComputerUseToolThroughBackend() async throws {
        let root = try makeTempDirectory()
        let backend = StubComputerUseBackend()
        let call = ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":42,"y":84}"#
        )
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            computerUseBackend: backend
        )

        model.setDraft("click 42 84")
        await model.submitComposer(workspaceRoot: root)

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, ["leftClick:42,84"])
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.computerClick.name)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Computer Use completed: Clicked 42 84."
        )
    }

    func testSubmitComposerCapturesComputerUseScreenshotThroughBackend() async throws {
        let root = try makeTempDirectory()
        let backend = StubComputerUseBackend(foregroundApplication: ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        ))
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            computerUseBackend: backend
        )

        model.setDraft("take a screenshot")
        await model.submitComposer(workspaceRoot: root)

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, ["screenshot"])
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.computerScreenshot.name)
        XCTAssertEqual(card.status, .done)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.stdout.contains(#""width" : 1"#))
        XCTAssertFalse(result.stdout.contains("pngBase64"))
        let screenshotOutput = try JSONHelpers.decode(ComputerScreenshotToolOutput.self, from: result.stdout)
        XCTAssertEqual(screenshotOutput.foregroundApplication?.name, "Terminal")
        XCTAssertEqual(screenshotOutput.foregroundApplication?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertTrue(screenshotOutput.visualSummary?.contains("foreground app: Terminal") == true)
        let screenshotArtifact = try XCTUnwrap(result.artifacts.first)
        defer {
            try? FileManager.default.removeItem(atPath: screenshotArtifact)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotArtifact))
        let artifact = try XCTUnwrap(card.artifacts.first)
        XCTAssertEqual(artifact.kind, .file)
        XCTAssertTrue(artifact.isImagePreview)
        XCTAssertEqual(artifact.previewURL, URL(fileURLWithPath: screenshotArtifact).absoluteString)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Captured a screenshot of Terminal (1 x 1). Preview artifact: `\(URL(fileURLWithPath: screenshotArtifact).lastPathComponent)`."
        )
    }

    func testSubmitComposerStreamsQueuedToolBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(
            llm: ImmediateToolLLMClient(),
            safety: SlowApprovingSafetyReviewer()
        ))

        model.setDraft("run pwd")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.currentToolCards.first?.status == .queued
        }
        XCTAssertTrue(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Queued")

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.currentToolCards.first?.status, .done)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
    }

    func testSubmitComposerShowsUserMessageAndThinkingBeforeAgentReturns() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))

        model.setDraft("run a slow task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.surface().transcript.timelineItems.first?.message?.text == "run a slow task"
        }
        XCTAssertEqual(model.composer.draft, "")
        XCTAssertTrue(model.composer.isSending)
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["run a slow task"])
        XCTAssertEqual(model.selectedThread?.events.map(\.kind), [.message])
        XCTAssertEqual(model.surface().transcript.thinking?.title, "Thinking")
        XCTAssertEqual(model.surface().transcript.thinking?.subtitle, "Preparing the next step")

        task.cancel()
        await task.value
    }

    func testSubmitComposerStartedCallbackReceivesOptimisticSurfaceBeforeAgentReturns() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))
        let recorder = StartedSurfaceRecorder()

        model.setDraft("show status quickly")
        let task = Task {
            await model.submitComposer(
                workspaceRoot: root,
                onStarted: {
                    recorder.record(model.surface())
                }
            )
        }

        try await waitUntil(timeoutSeconds: 1) {
            recorder.surface != nil
        }
        let surface = try XCTUnwrap(recorder.surface)
        XCTAssertEqual(surface.transcript.timelineItems.first?.message?.text, "show status quickly")
        XCTAssertEqual(surface.transcript.thinking?.title, "Thinking")
        XCTAssertTrue(surface.composer.isSending)

        task.cancel()
        await task.value
    }

    func testComposerShowsStreamingStatusForStreamingLLM() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(
            llm: DelayedStreamingSayLLMClient(chunks: [
                #"{"type":"say","text":"stream"#,
                #"ed response"}"#
            ])
        ))

        model.setDraft("say hello")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.root.topBar.agentStatus == "Streaming"
        }
        XCTAssertTrue(model.composer.isSending)
        try await waitUntil(timeoutSeconds: 1) {
            model.selectedThread?.messages.last?.content == "stream"
        }
        XCTAssertEqual(model.surface().transcript.timelineItems.last?.message?.text, "stream")
        XCTAssertEqual(model.surface().transcript.thinking?.title, "Streaming")

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "streamed response")
        // The trailing .notice is the post-run integrity stamp (#875), appended to every completed run.
        XCTAssertEqual(model.selectedThread?.events.map(\.kind), [.message, .notice, .message, .notice])
        XCTAssertEqual(model.selectedThread?.events[1].summary, AgentRunner.streamingNotice)
        XCTAssertEqual(model.selectedThread?.events.last?.summary, RunIntegrityRecord.eventSummary)
    }

    func testCancellingComposerRunStopsStateAndRecordsNotice() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))

        model.setDraft("run a long task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.root.topBar.agentStatus, "Stopped")
        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user])
        XCTAssertEqual(thread.messages.first?.content, "run a long task")
        XCTAssertTrue(thread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testCancelledComposerRunRecordsNoticeOnOriginalThread() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))
        let firstThreadID = model.newChat()

        model.setDraft("run a long task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }
        let secondThreadID = model.newChat()

        task.cancel()
        await task.value

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        let firstThread = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let secondThread = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertTrue(firstThread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
        XCTAssertFalse(secondThread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testCancellingSubagentSlashCommandPublishesCancelledProgressWithoutFinalSummary() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.subagentSchedulerOverride = WorkspaceSubagentScheduler { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return "unexpected completion"
        }

        model.setDraft("/subagents audit release | Worker: run slow check")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.root.topBar.agentStatus == TopBarAgentStatusLabel.running
        }
        task.cancel()
        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.stopped)
        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user])
        let update = try XCTUnwrap(SubagentProgressToolExecutor.latestUpdate(in: thread))
        XCTAssertEqual(update.subagents.map(\.status), [.cancelled])
    }

    func testSubagentSlashCommandExecutesWorkspaceToolsEndToEnd() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(
                llm: FixedToolLLMClient(call: ToolCall(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "delegated.txt",
                        "content": "delegated work\n"
                    ])
                )),
                safety: ImmediateApprovingSafetyReviewer()
            )
        )

        model.setDraft("/subagents create fixture | Builder: create delegated.txt containing delegated work")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("delegated.txt"), encoding: .utf8),
            "delegated work\n"
        )
        let thread = try XCTUnwrap(model.selectedThread)
        let update = try XCTUnwrap(SubagentProgressToolExecutor.latestUpdate(in: thread))
        XCTAssertEqual(update.subagents.map(\.status), [.completed])
        XCTAssertFalse(try XCTUnwrap(update.subagents.first?.summary).isEmpty)
    }

    func testCompletedSubagentRunStaysPinnedToOriginatingThreadAfterSelectionChanges() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.subagentSchedulerOverride = WorkspaceSubagentScheduler { _ in
            try await Task.sleep(nanoseconds: 200_000_000)
            return "finished on the original chat"
        }
        let originalThreadID = model.newChat()

        model.setDraft("/subagents audit release | Worker: inspect the project")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.root.topBar.agentStatus == TopBarAgentStatusLabel.running
        }
        let otherThreadID = model.newChat()
        await task.value

        XCTAssertEqual(model.root.selectedThreadID, otherThreadID)
        let original = try XCTUnwrap(model.root.threads.first { $0.id == originalThreadID })
        let other = try XCTUnwrap(model.root.threads.first { $0.id == otherThreadID })
        XCTAssertEqual(original.messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(original.messages.last?.content.contains("Subagents completed 1 worker") == true)
        XCTAssertNotNil(SubagentProgressToolExecutor.latestUpdate(in: original))
        XCTAssertTrue(other.messages.isEmpty)
        XCTAssertNil(SubagentProgressToolExecutor.latestUpdate(in: other))
    }

    func testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: DelayedStreamingSayLLMClient(chunks: [
                #"{"type":"say","text":"done"}"#
            ]))
        )
        let firstThreadID = model.newChat()

        model.setDraft("run a short task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }
        let secondThreadID = model.newChat()

        await task.value

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        let firstThread = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let secondThread = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertTrue(firstThread.messages.contains { $0.role == .assistant && $0.content == "done" })
        XCTAssertTrue(secondThread.messages.isEmpty)
    }

    func testBackgroundRunFailureLeavesADurableNoticeOnItsOwnThread() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowThrowingLLMClient()))
        let failingThreadID = model.newChat()

        model.setDraft("do the risky thing")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }
        // Navigate away BEFORE the run fails — this is exactly the case finishAgentRun drops (the
        // failing thread is no longer selected, so lastError never even gets set). The durable notice
        // is what lets the user see, on returning, that this background run failed.
        let otherThreadID = model.newChat()
        await task.value

        XCTAssertEqual(model.root.selectedThreadID, otherThreadID)
        let failed = try XCTUnwrap(model.root.threads.first { $0.id == failingThreadID })
        XCTAssertTrue(
            failed.events.contains { $0.kind == .notice && $0.summary.hasPrefix("Run stopped after an error") },
            "a background run that failed must leave a durable notice on its own thread"
        )
        let other = try XCTUnwrap(model.root.threads.first { $0.id == otherThreadID })
        XCTAssertFalse(
            other.events.contains { $0.kind == .notice && $0.summary.hasPrefix("Run stopped after an error") },
            "the failure notice belongs to the run's thread, not whichever thread is selected now"
        )
    }

    func testTwoThreadsRunConcurrentlyAndKeepIndependentPresentationState() async throws {
        let root = try makeTempDirectory()
        let gate = ConcurrentPromptGate()
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: ConcurrentPromptGateLLMClient(gate: gate))
        )
        let firstThreadID = model.newChat()

        model.setDraft("alpha task")
        let firstTask = Task {
            await model.submitComposer(threadID: firstThreadID, workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.isAgentRunActive(for: firstThreadID)
        }

        let secondThreadID = model.newChat()
        model.setDraft("beta task")
        let secondTask = Task {
            await model.submitComposer(threadID: secondThreadID, workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.activeAgentRunThreadIDs == [firstThreadID, secondThreadID]
        }
        try await waitUntilAsync(timeoutSeconds: 5) {
            await gate.hasStarted(["alpha task", "beta task"])
        }
        let bothModelCallsStarted = await gate.hasStarted(["alpha task", "beta task"])
        XCTAssertTrue(bothModelCallsStarted, "both model calls must be live concurrently")

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        XCTAssertTrue(model.composer.isSending)
        let runningRows = model.surface().sidebar.items.filter(\.isRunning)
        XCTAssertEqual(Set(runningRows.map(\.id)), [firstThreadID, secondThreadID])

        let idleThreadID = model.newChat()
        XCTAssertEqual(model.root.selectedThreadID, idleThreadID)
        XCTAssertFalse(model.composer.isSending, "an idle selected chat must keep an editable composer")
        XCTAssertEqual(model.root.topBar.agentStatus, "2 chats running")

        model.selectThread(firstThreadID)
        XCTAssertTrue(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.running)

        await gate.release("beta task")
        await secondTask.value
        XCTAssertEqual(model.root.selectedThreadID, firstThreadID, "a background completion must not steal selection")
        XCTAssertTrue(model.isAgentRunActive(for: firstThreadID))
        XCTAssertFalse(model.isAgentRunActive(for: secondThreadID))
        XCTAssertTrue(model.composer.isSending)

        await gate.release("alpha task")
        await firstTask.value
        XCTAssertTrue(model.activeAgentRunThreadIDs.isEmpty)
        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.idle)

        let first = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let second = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertTrue(first.messages.contains { $0.role == .assistant && $0.content == "Finished alpha task" })
        XCTAssertTrue(second.messages.contains { $0.role == .assistant && $0.content == "Finished beta task" })
    }

    func testExplicitThreadSubmissionUsesThatThreadsStashedDraftAfterSelectionChanges() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let firstThreadID = model.newChat()
        model.setDraft("send this to alpha")
        let secondThreadID = model.newChat()

        await model.submitComposer(threadID: firstThreadID, workspaceRoot: root)

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        let first = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let second = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertEqual(first.messages.first?.content, "send this to alpha")
        XCTAssertTrue(second.messages.isEmpty)
    }

    func testPreparingFirstAgentSubmissionMaterializesAStableTaskOwner() throws {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("inspect this project")

        let threadID = try XCTUnwrap(model.prepareComposerSubmissionThread())

        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.root.threads.map(\.id), [threadID])
        XCTAssertEqual(model.composer.draft, "inspect this project")
        XCTAssertEqual(model.root.threads.first?.composerDraft, "inspect this project")
    }

    func testPreparingViewOnlySlashCommandDoesNotCreateAChat() {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("/settings")

        XCTAssertNil(model.prepareComposerSubmissionThread())
        XCTAssertTrue(model.root.threads.isEmpty)
    }

    func testEmptyDraftDoesNotCreateThread() async throws {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("   ")

        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertTrue(model.root.threads.isEmpty)
        XCTAssertEqual(model.composer.draft, "   ")
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func waitUntilAsync(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !(await condition()) {
            if Date() > deadline {
                XCTFail("Timed out waiting for asynchronous condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func assertSideEffect(
        _ sideEffect: RealWorldSurfaceSideEffect?,
        workspaceRoot: URL,
        label: String
    ) throws {
        switch sideEffect {
        case .fileContains(let path, let text):
            let url = workspaceRoot.appendingPathComponent(path)
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(contents.contains(text), "\(label): \(url.path)")
        case .none:
            break
        }
    }

    private func normalizeToolInputJSON(_ inputJSON: String?) -> String {
        (inputJSON ?? "")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}

private struct RealWorldSurfaceCase {
    var prompt: String
    var toolName: String
    var inputContains: [String]
    var answerContains: String
    var sideEffect: RealWorldSurfaceSideEffect?
}

private enum RealWorldSurfaceSideEffect {
    case fileContains(path: String, text: String)
}

@MainActor
private final class StartedSurfaceRecorder {
    private(set) var surface: WorkspaceSurface?

    func record(_ surface: WorkspaceSurface) {
        self.surface = surface
    }
}

private struct SlowLLMClient: LLMClient {
    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return .say("late response")
    }
}

/// Blocks briefly (long enough for a test to navigate away, making the run a background one) and then
/// throws, driving the `.failed` outcome path for a non-selected thread.
private struct SlowThrowingLLMClient: LLMClient {
    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 200_000_000)
        throw BackgroundRunFailure.boom
    }
}

private enum BackgroundRunFailure: Error {
    case boom
}

private enum DelayedStreamingSayLLMError: Error {
    case nonStreamingPathUsed
}

private struct DelayedStreamingSayLLMClient: StreamingLLMClient {
    var chunks: [String]

    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        throw DelayedStreamingSayLLMError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    for (index, chunk) in chunks.enumerated() {
                        continuation.yield(chunk)
                        if index < chunks.count - 1 {
                            try await Task.sleep(nanoseconds: 150_000_000)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct ImmediateToolLLMClient: LLMClient {
    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        .tool(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "pwd"])
        ))
    }
}

private struct SlowApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        _ = context
        try? await Task.sleep(nanoseconds: 200_000_000)
        return SafetyReview(
            verdict: .approve,
            rationale: "The tool call is bounded and matches the current user request.",
            userIntentMatched: true
        )
    }
}

private struct ImmediateApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        _ = context
        return SafetyReview(
            verdict: .approve,
            rationale: "Approved in the workspace integration test.",
            userIntentMatched: true
        )
    }
}

private actor ConcurrentPromptGate {
    private var started: Set<String> = []
    private var released: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func wait(for prompt: String) async {
        started.insert(prompt)
        if released.remove(prompt) != nil { return }
        await withCheckedContinuation { continuation in
            waiters[prompt, default: []].append(continuation)
        }
    }

    func release(_ prompt: String) {
        let continuations = waiters.removeValue(forKey: prompt) ?? []
        if continuations.isEmpty {
            released.insert(prompt)
        } else {
            continuations.forEach { $0.resume() }
        }
    }

    func hasStarted(_ prompts: Set<String>) -> Bool {
        prompts.isSubset(of: started)
    }
}

private struct ConcurrentPromptGateLLMClient: LLMClient {
    var gate: ConcurrentPromptGate

    func nextAction(
        thread _: ChatThread,
        userMessage: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        await gate.wait(for: userMessage)
        return .say("Finished \(userMessage)")
    }
}
