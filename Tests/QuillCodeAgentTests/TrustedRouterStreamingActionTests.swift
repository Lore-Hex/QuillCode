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

    func testStreamingPreviewExposesOnlySayText() {
        XCTAssertEqual(
            AgentActionStreamPreview.visibleAssistantText(from: #"{"type":"say","text":"hello\nwor"#),
            "hello\nwor"
        )
        XCTAssertNil(AgentActionStreamPreview.visibleAssistantText(from: #"{"type":"tool","name":"host.shell.run","arguments":{"cmd":"printf text"}}"#))
        XCTAssertNil(AgentActionStreamPreview.visibleAssistantText(from: #"{"type":"say"}"#))
    }

    #if !os(Linux)
    func testDirectSSEDecoderPreservesReasoningTextAndUsage() async throws {
        let bytes = byteStream([
            #"data: {"choices":[{"delta":{"reasoning_content":"Inspect evidence."}}]}"# + "\n\n",
            #"data: {"choices":[{"delta":{"content":"{\"type\":\"say\",\"text\":\"done\"}"}}]}"# + "\n\n",
            #"data: {"choices":[],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}"# + "\n\n",
            "data: [DONE]\n\n",
        ])
        let decoded = TrustedRouterStreamingEventDecoder.eventStream(from: bytes, onTermination: {})

        var events: [AgentTextStreamEvent] = []
        for try await event in decoded {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .reasoning("Inspect evidence."))
        XCTAssertEqual(events[1], .text(#"{"type":"say","text":"done"}"#))
        guard case .usage(let usage) = events[2] else {
            return XCTFail("Expected a usage event")
        }
        XCTAssertEqual(usage.promptTokens, 11)
        XCTAssertEqual(usage.completionTokens, 7)
        XCTAssertEqual(usage.totalTokens, 18)
    }

    func testReasoningBudgetTerminatesDirectSSEProducer() async {
        let termination = StreamTerminationProbe()
        let bytes = byteStream([
            #"data: {"choices":[{"delta":{"reasoning_content":"12345678"}}]}"# + "\n\n",
            #"data: {"choices":[{"delta":{"content":"{\"type\":\"say\",\"text\":\"too late\"}"}}]}"# + "\n\n",
        ])
        let decoded = TrustedRouterStreamingEventDecoder.eventStream(from: bytes) {
            termination.record()
        }
        let guarded = AgentPreActionReasoningBudget.enforcing(
            maximumCharacters: 6,
            on: decoded
        )

        do {
            for try await _ in guarded {}
            XCTFail("Expected the reasoning budget to fire")
        } catch is AgentPreActionReasoningBudgetExceededError {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        for _ in 0..<100 where !termination.wasRecorded {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(termination.wasRecorded, "The direct transport must be cancelled promptly")
    }

    func testDirectSSEDecoderDoesNotDropEventsWhenConsumerIsSlow() async throws {
        let expected = (0..<64).map(String.init)
        let frames = expected.map { value in
            #"data: {"choices":[{"delta":{"content":""# + value + #""}}]}"# + "\n\n"
        }
        let decoded = TrustedRouterStreamingEventDecoder.eventStream(
            from: byteStream(frames),
            onTermination: {}
        )

        var received: [String] = []
        for try await event in decoded {
            guard case .text(let value) = event else { continue }
            received.append(value)
            try await Task.sleep(for: .milliseconds(1))
        }

        XCTAssertEqual(received, expected)
    }
    #endif

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

    private func byteStream(_ frames: [String]) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { continuation in
            for byte in frames.joined().utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }
    }
}

private final class StreamTerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = false

    var wasRecorded: Bool {
        lock.withLock { recorded }
    }

    func record() {
        lock.withLock { recorded = true }
    }
}
