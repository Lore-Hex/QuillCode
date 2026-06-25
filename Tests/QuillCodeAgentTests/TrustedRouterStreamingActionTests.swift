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
}
