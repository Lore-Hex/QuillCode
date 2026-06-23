import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTranscriptSurfaceBuilderTests: XCTestCase {
    func testMessageSurfacesHideToolMessagesAndAttachFeedback() throws {
        let user = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            role: .user,
            content: "run whoami"
        )
        let tool = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            role: .tool,
            content: "quill"
        )
        let assistant = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            role: .assistant,
            content: "You are `quill`."
        )
        let feedback = MessageFeedback(messageID: assistant.id, value: .helpful)
        let thread = ChatThread(
            messages: [user, tool, assistant],
            events: [
                ThreadEvent(
                    kind: .messageFeedback,
                    summary: "helpful",
                    payloadJSON: try JSONHelpers.encodePretty(feedback)
                )
            ]
        )

        let messages = WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertNil(messages.first?.feedback)
        XCTAssertEqual(messages.last?.feedback, .helpful)
    }

    func testToolCardsCollapseToolLifecycleAndAttachArtifacts() throws {
        let call = ToolCall(
            id: "tool-call-1",
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "hello.txt", "content": "hello"])
        )
        let result = ToolResult(ok: true, stdout: "wrote hello.txt\n", artifacts: ["hello.txt"])
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: try JSONHelpers.encodePretty(result))
        ])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].id, "tool-call-1")
        XCTAssertEqual(cards[0].title, ToolDefinition.fileWrite.name)
        XCTAssertEqual(cards[0].subtitle, "Completed · hello.txt")
        XCTAssertEqual(cards[0].status, .done)
        XCTAssertEqual(cards[0].inputJSON, call.argumentsJSON)
        XCTAssertEqual(cards[0].artifacts.map(\.label), ["hello.txt"])
    }

    func testTimelineFollowsThreadEventsAndAppendsUnmatchedMessages() throws {
        let user = ChatMessage(role: .user, content: "run whoami")
        let assistant = ChatMessage(role: .assistant, content: "You are `quill`.")
        let unmatchedAssistant = ChatMessage(role: .assistant, content: "One more note.")
        let call = ToolCall(
            id: "shell-1",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let result = ToolResult(ok: true, stdout: "quill\n")
        let thread = ChatThread(
            messages: [user, assistant, unmatchedAssistant],
            events: [
                ThreadEvent(kind: .message, summary: user.content),
                ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .message, summary: assistant.content)
            ]
        )

        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()

        XCTAssertEqual(timeline.map(\.kind), [.message, .toolCard, .message, .message])
        XCTAssertEqual(timeline[0].message?.text, user.content)
        XCTAssertEqual(timeline[1].toolCard?.id, "shell-1")
        XCTAssertEqual(timeline[1].toolCard?.status, .done)
        XCTAssertEqual(timeline[1].toolCard?.subtitle, "Completed · whoami")
        XCTAssertEqual(timeline[2].message?.text, assistant.content)
        XCTAssertEqual(timeline[3].message?.text, unmatchedAssistant.content)
    }

    func testSafetyReviewAndOrphanToolEventsRemainVisible() throws {
        let failedResult = ToolResult(ok: false, error: "stopped")
        let thread = ChatThread(events: [
            ThreadEvent(kind: .approvalRequested, summary: "approve shell", payloadJSON: #"{"cmd":"ls"}"#),
            ThreadEvent(kind: .toolFailed, summary: "failed", payloadJSON: try JSONHelpers.encodePretty(failedResult))
        ])

        let timelineCards = WorkspaceTranscriptSurfaceBuilder(thread: thread)
            .timelineItems()
            .compactMap(\.toolCard)

        XCTAssertEqual(timelineCards.count, 2)
        XCTAssertEqual(timelineCards[0].title, "Safety Check")
        XCTAssertEqual(timelineCards[0].status, .review)
        XCTAssertTrue(timelineCards[0].isExpanded)
        XCTAssertEqual(timelineCards[1].title, "Tool")
        XCTAssertEqual(timelineCards[1].status, .failed)
        XCTAssertEqual(timelineCards[1].subtitle, "Failed")
    }

    func testToolCardSubtitleBuilderSummarizesKnownArguments() {
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Running",
                toolName: "host.shell.run",
                inputJSON: ToolArguments.json(["cmd": "printf 'hello'\n && whoami"])
            ),
            "Running · printf 'hello' && whoami"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.git.diff",
                inputJSON: ToolArguments.json(["staged": true])
            ),
            "Completed · staged diff"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.git.push",
                inputJSON: ToolArguments.json(["remote": "origin", "branch": "main"])
            ),
            "Completed · origin/main"
        )
    }

    func testToolCardSubtitleBuilderFallsBackForInvalidOrUnknownInput() {
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.shell.run",
                inputJSON: "{}"
            ),
            "Completed"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.unknown",
                inputJSON: ToolArguments.json(["cmd": "whoami"])
            ),
            "Completed"
        )
    }
}
