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
        let backend = StubComputerUseBackend()
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
            "Captured a screenshot (1 x 1)."
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

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "streamed response")
        XCTAssertEqual(model.selectedThread?.events.map(\.kind), [.message, .notice, .message])
        XCTAssertEqual(model.selectedThread?.events[1].summary, AgentRunner.streamingNotice)
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
