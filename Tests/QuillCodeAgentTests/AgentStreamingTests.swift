import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentStreamingTests: XCTestCase {
    func testCancellingBeforeModelActionPublishesStoppedNotice() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let runner = AgentRunner(llm: NeverReturningLLMClient())

        let task = Task {
            try await runner.send(
                "run a long task",
                in: ChatThread(mode: .auto),
                workspaceRoot: root,
                onProgress: { thread in
                    await recorder.record(thread)
                }
            )
        }
        try await waitUntil(timeoutSeconds: 1) {
            await recorder.eventKinds() == [.message]
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            let snapshots = await recorder.eventSnapshots()
            XCTAssertEqual(snapshots.last?.map(\.kind), [.message, .notice])
            XCTAssertEqual(snapshots.last?.last?.summary, AgentCancellationRecorder.stoppedSummary)
        }
    }

    func testCancellingRunningToolPublishesStoppedToolFailure() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "sleep 5"])
        )
        let runner = AgentRunner(
            llm: FixedToolLLMClient(call: call),
            toolExecutionOverride: { _, _ in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                return ToolResult(ok: false, error: "Override noticed cancellation.")
            }
        )

        let task = Task {
            try await runner.send(
                "run a long shell command",
                in: ChatThread(mode: .auto),
                workspaceRoot: root,
                onProgress: { thread in
                    await recorder.record(thread)
                }
            )
        }
        try await waitUntil(timeoutSeconds: 1) {
            await recorder.eventKinds().contains(.toolRunning)
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            let snapshots = await recorder.eventSnapshots()
            let snapshot = try XCTUnwrap(snapshots.last)
            XCTAssertEqual(snapshot.map(\.kind), [.message, .toolQueued, .toolRunning, .toolFailed, .notice])
            XCTAssertEqual(snapshot[snapshot.count - 2].summary, AgentCancellationRecorder.stoppedSummary)
            XCTAssertEqual(snapshot[snapshot.count - 2].payloadJSON, AgentCancellationRecorder.stoppedPayloadJSON)
            XCTAssertEqual(snapshot.last?.summary, AgentCancellationRecorder.stoppedSummary)
        }
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
        XCTAssertEqual(eventKinds, [.message, .toolQueued, .toolRunning, .toolCompleted, .message])
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
        XCTAssertEqual(
            eventKinds,
            [.message, .notice, .toolQueued, .toolRunning, .toolCompleted, .notice, .message]
        )
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

    func testUsageStreamingSayActionRecordsProviderTokenUsage() async throws {
        let root = try makeTempDirectory()
        let usage = ModelTokenUsage(promptTokens: 25_000, completionTokens: 500, totalTokens: 25_500)
        let runner = AgentRunner(llm: UsageStreamingActionLLMClient(events: [
            .text(#"{"type":"say","text":"hello"}"#),
            .usage(usage)
        ]))

        let result = try await runner.send(
            "say hello",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let recordedUsage = result.thread.events.compactMap(ModelTokenUsageEvent.usage(from:)).last
        XCTAssertEqual(recordedUsage, usage)
        let recordedModelID = result.thread.events.compactMap(ModelTokenUsageEvent.record(from:)).last?.modelID
        XCTAssertEqual(recordedModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(result.thread.messages.last?.content, "hello")
    }

    func testUsageStreamingToolActionRecordsProviderTokenUsageBeforeToolEvents() async throws {
        let root = try makeTempDirectory()
        let usage = ModelTokenUsage(promptTokens: 10_000, completionTokens: 80, totalTokens: 10_080)
        let runner = AgentRunner(llm: UsageStreamingActionLLMClient(events: [
            .text(#"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}"#),
            .usage(usage)
        ]))

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertEqual(result.thread.events.compactMap(ModelTokenUsageEvent.usage(from:)).last, usage)
        let usageEventIndex = try XCTUnwrap(result.thread.events.firstIndex {
            ModelTokenUsageEvent.usage(from: $0) == usage
        })
        let queuedEventIndex = try XCTUnwrap(result.thread.events.firstIndex { $0.kind == .toolQueued })
        XCTAssertLessThan(usageEventIndex, queuedEventIndex)
        XCTAssertEqual(result.thread.events[1].summary, AgentRunner.streamingNotice)
    }

    func testUsageStreamingToolActionPausesAtSpendFuseBeforeToolRuns() async throws {
        let root = try makeTempDirectory()
        let usage = ModelTokenUsage(promptTokens: 2_000, completionTokens: 1_000)
        let policy = try XCTUnwrap(RunSpendFusePolicy(
            fuseUSD: 0.01,
            modelCatalog: [
                ModelInfo(
                    id: TrustedRouterDefaults.defaultModel,
                    provider: "trustedrouter",
                    displayName: "Nike 1.0",
                    category: "Fast",
                    capabilities: ModelCapabilities(
                        inputPricePerMillionTokens: 2.0,
                        outputPricePerMillionTokens: 6.0
                    )
                )
            ]
        ))
        let runner = AgentRunner(
            llm: UsageStreamingActionLLMClient(events: [
                .text(#"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}"#),
                .usage(usage)
            ]),
            runSpendFusePolicy: policy
        )

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.stopReason, .spendFuseApprovalRequired(totalUSD: 0.01, fuseUSD: 0.01))
        XCTAssertTrue(result.thread.events.contains { $0.kind == .approvalRequested })
        XCTAssertFalse(result.thread.events.contains { $0.kind == .toolQueued })
        let request = try XCTUnwrap(result.thread.events.compactMap { event -> ApprovalRequest? in
            guard event.kind == .approvalRequested, let payloadJSON = event.payloadJSON else { return nil }
            return try? JSONHelpers.decode(ApprovalRequest.self, from: payloadJSON)
        }.last)
        XCTAssertEqual(request.scope, .runSpendFuse)
        XCTAssertEqual(request.toolCall.name, RunSpendFusePolicy.toolName)
        XCTAssertEqual(result.thread.messages.last?.content, "Thread spend reached $0.01. Approve to continue this run.")
    }

    func testUsageStreamingReasoningSummariesAreRecordedAsThinkingTrace() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let runner = AgentRunner(llm: UsageStreamingActionLLMClient(events: [
            .reasoning("Inspecting the request."),
            .reasoning("Choosing the shell tool."),
            .text(#"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}"#)
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
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary == "Thinking: Inspecting the request."
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary == "Thinking: Choosing the shell tool."
        })

        let snapshots = await recorder.eventSnapshots()
        XCTAssertTrue(snapshots.contains { events in
            events.last?.kind == .notice &&
                events.last?.summary == "Thinking: Inspecting the request."
        })
        XCTAssertTrue(snapshots.contains { events in
            events.last?.kind == .notice &&
                events.last?.summary == "Thinking: Choosing the shell tool."
        })
    }

    func testStreamingPromisedWorkDraftIsSuppressedBeforeCorrectionToolRuns() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let runner = AgentRunner(llm: PromiseThenToolStreamingLLMClient(
            promisedChunks: [
                #"{"type":"say","text":"I'll"#,
                #" run `whoami` now."}"#
            ],
            toolChunks: [
                #"{"type":"tool","#,
                #""name":"host.shell.run","#,
                #""arguments":{"cmd":"whoami"}}"#
            ]
        ))

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
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("I'll run") })
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)

        let progressMessages = await recorder.messageContents()
        XCTAssertFalse(progressMessages.contains { snapshot in
            snapshot.contains { $0.contains("I'll run") }
        })
    }

    func testStreamingPromisedShellTextRecoversWithoutVisibleDraftOrCorrectionPrompt() async throws {
        let root = try makeTempDirectory()
        let recorder = ProgressRecorder()
        let runner = AgentRunner(llm: StreamingActionLLMClient(chunks: [
            #"{"type":"say","text":"I'll"#,
            #" run whoami on the device."}"#
        ]))

        let result = try await runner.send(
            "whoami?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root,
            onProgress: { thread in
                await recorder.record(thread)
            }
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("I'll run") })
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)

        let progressMessages = await recorder.messageContents()
        XCTAssertFalse(progressMessages.contains { snapshot in
            snapshot.contains { $0.contains("I'll run") }
        })
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }
}

private actor StreamingRetryState {
    private var didUsePromise = false
    private let promisedChunks: [String]
    private let toolChunks: [String]

    init(promisedChunks: [String], toolChunks: [String]) {
        self.promisedChunks = promisedChunks
        self.toolChunks = toolChunks
    }

    func nextChunks() -> [String] {
        if didUsePromise {
            return toolChunks
        }
        didUsePromise = true
        return promisedChunks
    }
}

private struct PromiseThenToolStreamingLLMClient: StreamingLLMClient {
    private let state: StreamingRetryState

    init(promisedChunks: [String], toolChunks: [String]) {
        self.state = StreamingRetryState(
            promisedChunks: promisedChunks,
            toolChunks: toolChunks
        )
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        let stream = try await actionTextStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        return try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: AgentError.emptyStreamingResponse
        )
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let chunks = await state.nextChunks()
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private struct NeverReturningLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
