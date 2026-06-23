import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeTranscriptFindTests: XCTestCase {
    func testFindMatchesMessagesAndToolCardDetails() {
        let userMessage = MessageSurface(message: ChatMessage(role: .user, content: "Run tests"))
        let assistantMessage = MessageSurface(message: ChatMessage(role: .assistant, content: "All checks passed"))
        let toolCard = ToolCardState(
            id: "tool-1",
            title: "Run Shell",
            subtitle: "swift test",
            status: .done,
            inputJSON: #"{"command":"swift test"}"#,
            outputJSON: #"{"stdout":"ok"}"#,
            artifacts: [.init(value: "/tmp/report.txt")]
        )
        let transcript = TranscriptSurface(
            messages: [userMessage, assistantMessage],
            toolCards: [toolCard]
        )

        XCTAssertEqual(
            QuillCodeTranscriptFindMatch.matches(in: transcript, query: "checks").map(\.label),
            ["Assistant"]
        )
        XCTAssertEqual(
            QuillCodeTranscriptFindMatch.matches(in: transcript, query: "swift").map(\.label),
            ["Run Shell"]
        )
        XCTAssertEqual(
            QuillCodeTranscriptFindMatch.matches(in: transcript, query: "report").map(\.label),
            ["Run Shell"]
        )
    }

    func testFindIgnoresBlankQueries() {
        let transcript = TranscriptSurface(
            messages: [MessageSurface(message: ChatMessage(role: .user, content: "hello"))],
            toolCards: []
        )

        XCTAssertEqual(QuillCodeTranscriptFindMatch.matches(in: transcript, query: ""), [])
        XCTAssertEqual(QuillCodeTranscriptFindMatch.matches(in: transcript, query: "   "), [])
    }
}
