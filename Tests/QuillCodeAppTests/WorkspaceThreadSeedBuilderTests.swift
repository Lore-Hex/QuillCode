import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceThreadSeedBuilderTests: XCTestCase {
    func testTitleUsesFirstSixWordsOrNewChatFallback() {
        XCTAssertEqual(
            WorkspaceThreadSeedBuilder.title(fromUserPrompt: "  build a fast trusted router model picker today  "),
            "build a fast trusted router model"
        )
        XCTAssertEqual(WorkspaceThreadSeedBuilder.title(fromUserPrompt: " \n\t "), "New chat")
    }

    func testForkSeedStartsAtLatestUserTurnAndHidesToolMessages() {
        let messages = [
            ChatMessage(role: .user, content: "old request"),
            ChatMessage(role: .assistant, content: "old answer"),
            ChatMessage(role: .user, content: "latest request"),
            ChatMessage(role: .tool, content: #"{"internal":"hidden"}"#),
            ChatMessage(role: .assistant, content: "latest answer"),
            ChatMessage(role: .assistant, content: "follow-up detail")
        ]

        let seed = WorkspaceThreadSeedBuilder.forkSeedMessages(from: messages)

        XCTAssertEqual(seed.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(seed.map(\.content), [
            "latest request",
            "latest answer",
            "follow-up detail"
        ])
    }

    func testForkSeedWithoutUserKeepsLatestFourVisibleMessages() {
        let messages = [
            ChatMessage(role: .assistant, content: "one"),
            ChatMessage(role: .tool, content: "hidden"),
            ChatMessage(role: .assistant, content: "two"),
            ChatMessage(role: .assistant, content: "three"),
            ChatMessage(role: .assistant, content: "four"),
            ChatMessage(role: .assistant, content: "five")
        ]

        let seed = WorkspaceThreadSeedBuilder.forkSeedMessages(from: messages)

        XCTAssertEqual(seed.map(\.content), ["two", "three", "four", "five"])
    }

    func testSummarizedForkSeedSummarizesOlderVisibleContextAndKeepsRecentTurn() {
        let thread = ChatThread(title: "Large fork", messages: [
            ChatMessage(role: .system, content: "system context"),
            ChatMessage(role: .user, content: "old request\nwith spacing"),
            ChatMessage(role: .assistant, content: String(repeating: "long ", count: 60)),
            ChatMessage(role: .user, content: "latest request"),
            ChatMessage(role: .tool, content: #"{"internal":"hidden continuation feedback"}"#),
            ChatMessage(role: .assistant, content: "latest answer")
        ])

        let seed = WorkspaceThreadSeedBuilder.summarizedForkSeedMessages(from: thread)

        XCTAssertEqual(seed.count, 3)
        XCTAssertEqual(seed[1].content, "latest request")
        XCTAssertEqual(seed[2].content, "latest answer")
        XCTAssertTrue(seed[0].content.contains("Context forked from \"Large fork\" with a summary."))
        XCTAssertTrue(seed[0].content.contains("summarized 3 earlier messages"))
        XCTAssertTrue(seed[0].content.contains("- User: old request with spacing"))
        XCTAssertTrue(seed[0].content.contains("Continue the fork from the preserved latest turn below."))
        XCTAssertFalse(seed[0].content.contains("hidden continuation feedback"))
    }

    func testFullContextForkSeedKeepsAllVisibleMessages() {
        let messages = [
            ChatMessage(role: .user, content: "old request"),
            ChatMessage(role: .assistant, content: "old answer"),
            ChatMessage(role: .tool, content: #"{"hidden":true}"#),
            ChatMessage(role: .user, content: "latest request"),
            ChatMessage(role: .assistant, content: "latest answer")
        ]

        let seed = WorkspaceThreadSeedBuilder.fullContextSeedMessages(from: messages)

        XCTAssertEqual(seed.map(\.content), [
            "old request",
            "old answer",
            "latest request",
            "latest answer"
        ])
    }

    func testCompactSeedSummarizesOlderVisibleContextAndKeepsRecentTurn() {
        let messages = [
            ChatMessage(role: .system, content: "system context"),
            ChatMessage(role: .user, content: "old request\nwith spacing"),
            ChatMessage(role: .assistant, content: String(repeating: "long ", count: 60)),
            ChatMessage(role: .user, content: "latest request"),
            ChatMessage(role: .tool, content: #"{"internal":"hidden continuation feedback"}"#),
            ChatMessage(role: .assistant, content: "latest answer")
        ]
        let thread = ChatThread(title: "Large context", messages: messages)

        let seed = WorkspaceThreadSeedBuilder.compactSeedMessages(from: thread)

        XCTAssertEqual(seed.count, 3)
        XCTAssertEqual(seed[1].content, "latest request")
        XCTAssertEqual(seed[2].content, "latest answer")
        XCTAssertTrue(seed[0].content.contains("Context compacted from \"Large context\""))
        XCTAssertTrue(seed[0].content.contains("summarized 3 earlier messages"))
        XCTAssertTrue(seed[0].content.contains("- User: old request with spacing"))
        XCTAssertTrue(seed[0].content.contains("..."))
        XCTAssertFalse(seed[0].content.contains("hidden continuation feedback"))
    }

    func testCompactSeedReportsWhenNothingWasDropped() {
        let thread = ChatThread(title: "Short context", messages: [
            ChatMessage(role: .user, content: "latest request"),
            ChatMessage(role: .assistant, content: "latest answer")
        ])

        let seed = WorkspaceThreadSeedBuilder.compactSeedMessages(from: thread)

        XCTAssertEqual(Array(seed.map(\.content).suffix(2)), ["latest request", "latest answer"])
        XCTAssertTrue(seed.first?.content.contains("No earlier turns were dropped.") == true)
    }
}
