import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class TrustedRouterStreamingActionTests: XCTestCase {
    func testCollectActionParsesSplitStreamingText() async throws {
        let action = try await TrustedRouterLLMClient.collectAction(from: stream([
            #"{"type":"tool","#,
            #""name":"host.shell.run","#,
            #""arguments":{"cmd":"whoami"}}"#
        ]))

        guard case .tool(let call) = action else {
            return XCTFail("Expected streamed tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertTrue(call.argumentsJSON.contains("whoami"))
    }

    func testCollectActionRejectsEmptyStream() async {
        do {
            _ = try await TrustedRouterLLMClient.collectAction(from: stream([]))
            XCTFail("Expected empty stream to throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("empty response"))
        }
    }

    func testCollectActionPublishesChangingVisibleAssistantDrafts() async throws {
        var drafts: [String] = []
        let action = try await AgentActionStreamCollector.collect(
            from: stream([
                #"{"type":"say","text":""#,
                #"hel"#,
                #"lo"#,
                #""}"#
            ]),
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: { draft in
                drafts.append(draft)
            }
        )

        XCTAssertEqual(drafts, ["hel", "hello"])
        XCTAssertEqual(action, .say("hello"))
    }

    func testCollectActionCoalescesRapidVisibleDraftsAndFlushesFinalText() async throws {
        let finalText = String(repeating: "x", count: 4_096)
        let events = [AgentTextStreamEvent.text(#"{"type":"say","text":""#)]
            + finalText.map { .text(String($0)) }
            + [.text(#""}"#)]
        var drafts: [String] = []

        let action = try await AgentActionStreamCollector.collect(
            from: eventStream(events),
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: { drafts.append($0) },
            onUsage: nil,
            onReasoning: nil,
            maximumActionUTF8Bytes: 32 * 1_024,
            previewIntervalNanoseconds: 50_000_000,
            nowNanoseconds: { 1 }
        )

        XCTAssertEqual(action, .say(finalText))
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.first, "x")
        XCTAssertEqual(drafts.last, finalText)
    }

    func testCollectActionFlushesLatestSafePreviewBeforeStreamFailure() async {
        var drafts: [String] = []
        let brokenStream = AsyncThrowingStream<AgentTextStreamEvent, Error> { continuation in
            continuation.yield(.text(#"{"type":"say","text":""#))
            continuation.yield(.text("hel"))
            continuation.yield(.text("lo"))
            continuation.finish(throwing: StreamingProbeError.disconnected)
        }

        do {
            _ = try await AgentActionStreamCollector.collect(
                from: brokenStream,
                emptyError: AgentError.emptyStreamingResponse,
                onVisibleAssistantText: { drafts.append($0) },
                onUsage: nil,
                onReasoning: nil,
                maximumActionUTF8Bytes: 1_024,
                previewIntervalNanoseconds: 50_000_000,
                nowNanoseconds: { 1 }
            )
            XCTFail("Expected the provider stream failure")
        } catch StreamingProbeError.disconnected {
            XCTAssertEqual(drafts, ["hel", "hello"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCollectActionRejectsResponseBeyondUTF8ByteBudget() async {
        do {
            _ = try await AgentActionStreamCollector.collect(
                from: eventStream([.text(String(repeating: "x", count: 33))]),
                emptyError: AgentError.emptyStreamingResponse,
                onVisibleAssistantText: nil,
                onUsage: nil,
                onReasoning: nil,
                maximumActionUTF8Bytes: 32,
                previewIntervalNanoseconds: 50_000_000,
                nowNanoseconds: { 1 }
            )
            XCTFail("Expected the response budget to reject the stream")
        } catch let AgentError.streamingActionTooLarge(maximumBytes) {
            XCTAssertEqual(maximumBytes, 32)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCollectActionPublishesReasoningSummariesSeparatelyFromText() async throws {
        var reasoning: [String] = []
        let action = try await AgentActionStreamCollector.collect(
            from: eventStream([
                .reasoning("Inspecting request."),
                .reasoning("Inspecting request."),
                .reasoning("Choosing shell."),
                .text(#"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}"#)
            ]),
            emptyError: AgentError.emptyStreamingResponse,
            onVisibleAssistantText: nil,
            onUsage: nil,
            onReasoning: { summary in
                reasoning.append(summary)
            }
        )

        XCTAssertEqual(reasoning, ["Inspecting request.", "Choosing shell."])
        guard case .tool(let call) = action else {
            return XCTFail("Expected streamed tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
    }

    func testReasoningAccumulatorPreservesTokenWhitespaceAndBoundsPresentation() {
        var accumulator = AgentReasoningStreamAccumulator()

        XCTAssertEqual(accumulator.append("Reason"), "Reason")
        XCTAssertEqual(accumulator.append("ing"), "Reasoning")
        XCTAssertNil(accumulator.append(" "))
        XCTAssertEqual(accumulator.append("works"), "Reasoning works")
        XCTAssertEqual(accumulator.append("."), "Reasoning works.")

        let oversized = String(repeating: "x", count: AgentReasoningStreamAccumulator.maximumCharacters + 40)
        XCTAssertEqual(accumulator.append(oversized)?.count, AgentReasoningStreamAccumulator.maximumCharacters)
        XCTAssertEqual(accumulator.text.count, AgentReasoningStreamAccumulator.maximumCharacters)
    }

    func testReasoningAccumulatorRecognizesGrowingSnapshots() {
        var accumulator = AgentReasoningStreamAccumulator()

        XCTAssertEqual(accumulator.append("First"), "First")
        XCTAssertEqual(accumulator.append("First second"), "First second")
        XCTAssertEqual(accumulator.text, "First second")
    }

    func testReasoningAccumulatorCoalescesRapidProgressAndFlushesFinalSummary() {
        var accumulator = AgentReasoningStreamAccumulator()

        XCTAssertEqual(accumulator.appendThrottled("First", nowNanoseconds: 1), "First")
        XCTAssertNil(accumulator.appendThrottled(" second", nowNanoseconds: 2))
        XCTAssertNil(accumulator.appendThrottled(" third", nowNanoseconds: 3))
        XCTAssertEqual(accumulator.finalPendingSummary(), "First second third")
        XCTAssertNil(accumulator.finalPendingSummary())
    }

    func testStreamingPreviewExposesOnlySayText() {
        XCTAssertEqual(
            AgentActionStreamPreview.visibleAssistantText(from: #"{"type":"say","text":"hello\nwor"#),
            "hello\nwor"
        )
        XCTAssertNil(AgentActionStreamPreview.visibleAssistantText(from: #"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"printf text"}}"#))
        XCTAssertNil(AgentActionStreamPreview.visibleAssistantText(from: #"{"type":"say"}"#))
    }

    private func stream(_ chunks: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func eventStream(_ events: [AgentTextStreamEvent]) -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private enum StreamingProbeError: Error {
    case disconnected
}
