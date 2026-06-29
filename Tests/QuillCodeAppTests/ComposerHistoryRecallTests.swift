import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class ComposerHistoryRecallTests: XCTestCase {
    private func userMessages(_ texts: [String]) -> [ChatMessage] {
        texts.map { ChatMessage(role: .user, content: $0) }
    }

    func testHistoryKeepsNonEmptyUserMessagesOldestFirst() {
        let messages = [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "answer"),
            ChatMessage(role: .tool, content: "tool feedback"),
            ChatMessage(role: .user, content: "  second  ")
        ]
        XCTAssertEqual(ComposerHistoryRecall.history(from: messages), ["first", "second"])
    }

    func testHistorySkipsBlankUserMessages() {
        let messages = userMessages(["real", "   ", "\n"])
        XCTAssertEqual(ComposerHistoryRecall.history(from: messages), ["real"])
    }

    func testHistoryCollapsesAdjacentDuplicates() {
        let messages = userMessages(["run tests", "run tests", "build", "run tests"])
        XCTAssertEqual(ComposerHistoryRecall.history(from: messages), ["run tests", "build", "run tests"])
    }

    func testHistoryBoundsToMaxEntries() {
        let messages = userMessages((0..<(ComposerHistoryRecall.maxEntries + 10)).map { "msg-\($0)" })
        let history = ComposerHistoryRecall.history(from: messages)
        XCTAssertEqual(history.count, ComposerHistoryRecall.maxEntries)
        XCTAssertEqual(history.first, "msg-10")
        XCTAssertEqual(history.last, "msg-\(ComposerHistoryRecall.maxEntries + 9)")
    }

    func testOlderStartsAtNewestThenWalksBack() {
        let history = ["a", "b", "c"]
        XCTAssertEqual(ComposerHistoryRecall.older(history: history, currentIndex: nil), .init(index: 2, draft: "c"))
        XCTAssertEqual(ComposerHistoryRecall.older(history: history, currentIndex: 2), .init(index: 1, draft: "b"))
        XCTAssertEqual(ComposerHistoryRecall.older(history: history, currentIndex: 1), .init(index: 0, draft: "a"))
        // Clamps at the oldest entry.
        XCTAssertEqual(ComposerHistoryRecall.older(history: history, currentIndex: 0), .init(index: 0, draft: "a"))
    }

    func testOlderOnEmptyHistoryReturnsNil() {
        XCTAssertNil(ComposerHistoryRecall.older(history: [], currentIndex: nil))
    }

    func testNewerWalksForwardThenExitsPastNewest() {
        let history = ["a", "b", "c"]
        XCTAssertEqual(ComposerHistoryRecall.newer(history: history, currentIndex: 0), .init(index: 1, draft: "b"))
        XCTAssertEqual(ComposerHistoryRecall.newer(history: history, currentIndex: 1), .init(index: 2, draft: "c"))
        // Stepping past the newest entry exits recall.
        XCTAssertNil(ComposerHistoryRecall.newer(history: history, currentIndex: 2))
    }
}
