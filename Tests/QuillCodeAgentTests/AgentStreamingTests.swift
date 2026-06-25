import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentStreamingTests: XCTestCase {
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
        XCTAssertEqual(eventKinds, [.message, .toolQueued, .toolRunning, .message])
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
        XCTAssertEqual(eventKinds, [.message, .notice, .toolQueued, .toolRunning, .notice, .message])
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
}
