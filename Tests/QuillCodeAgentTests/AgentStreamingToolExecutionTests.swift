import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentStreamingToolExecutionTests: XCTestCase {
    func testStreamingOverridePublishesProgressAndPersistsOnlyLatestSnapshot() async throws {
        let call = shellCall(id: "streaming-shell")
        let recorder = ProgressRecorder()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Done.")]),
            streamingToolExecutionOverride: { _, _ in
                Self.stream([
                    .progress(.init(completed: 10, total: 100, message: "Indexing")),
                    .progress(.init(completed: 75, total: 100, message: "Writing")),
                    .result(ToolResult(ok: true, stdout: "complete"))
                ])
            }
        )

        let result = try await runner.send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory(),
            onProgress: { await recorder.record($0) }
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "complete")
        XCTAssertEqual(result.thread.events.map(\.kind), [
            .message, .toolQueued, .toolRunning, .toolProgress, .toolCompleted, .message
        ])
        let progressEvent = try XCTUnwrap(result.thread.events.first { $0.kind == .toolProgress })
        let payload = try JSONHelpers.decode(
            ToolProgressEventPayload.self,
            from: XCTUnwrap(progressEvent.payloadJSON)
        )
        XCTAssertEqual(payload.toolCallID, call.id)
        XCTAssertEqual(payload.progress, .init(completed: 75, total: 100, message: "Writing"))
        let recordedKinds = await recorder.eventKinds()
        XCTAssertEqual(recordedKinds.filter { $0 == .toolProgress }.count, 2)
        XCTAssertEqual(recordedKinds.suffix(2), [.toolCompleted, .message])
    }

    func testStreamingOverrideFailsClosedWithoutExactlyOneFinalResult() async throws {
        let noResult = try await run(events: [.progress(.init(completed: 1, total: 2))])
        XCTAssertEqual(noResult.toolResults.first?.error, "The streaming tool finished without a final result.")
        XCTAssertEqual(noResult.thread.events.first { $0.kind == .toolFailed }?.summary, "host.shell.run failed")

        let duplicateResult = try await run(events: [
            .result(ToolResult(ok: true, stdout: "first")),
            .result(ToolResult(ok: true, stdout: "second"))
        ])
        XCTAssertEqual(
            duplicateResult.toolResults.first?.error,
            "The streaming tool returned more than one final result."
        )
    }

    func testCancellingAfterProgressClosesTheActiveToolLifecycle() async throws {
        let call = shellCall(id: "cancelled-stream")
        let recorder = ProgressRecorder()
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call)]),
            streamingToolExecutionOverride: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.progress(.init(completed: 1, total: 10, message: "Starting")))
                    continuation.onTermination = { _ in }
                }
            }
        )
        let task = Task {
            try await runner.send(
                "run whoami",
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory(),
                onProgress: { await recorder.record($0) }
            )
        }
        try await waitUntil(timeoutSeconds: 1) {
            await recorder.eventKinds().contains(.toolProgress)
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            let snapshots = await recorder.eventSnapshots()
            let last = try XCTUnwrap(snapshots.last)
            XCTAssertEqual(last.suffix(2).map(\.kind), [.toolFailed, .notice])
            XCTAssertEqual(last[last.count - 2].summary, AgentCancellationRecorder.stoppedSummary)
        }
    }

    private func run(events: [AgentStreamingToolExecutionEvent]) async throws -> AgentRunResult {
        let call = shellCall(id: UUID().uuidString)
        return try await AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Done.")]),
            streamingToolExecutionOverride: { _, _ in Self.stream(events) }
        ).send(
            "run whoami",
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )
    }

    private func shellCall(id: String) -> ToolCall {
        ToolCall(
            id: id,
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
    }

    private static func stream(
        _ events: [AgentStreamingToolExecutionEvent]
    ) -> AsyncThrowingStream<AgentStreamingToolExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }
}
