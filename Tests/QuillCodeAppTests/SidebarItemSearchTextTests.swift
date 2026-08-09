import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class SidebarItemSearchTextTests: XCTestCase {
    func testSearchTextPreservesRelevantMessageOrderAndSeparators() {
        let messages = [
            ChatMessage(role: .system, content: "hidden system"),
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .tool, content: "hidden tool"),
            ChatMessage(role: .assistant, content: ""),
            ChatMessage(role: .user, content: "third"),
        ]

        XCTAssertEqual(searchText(for: messages), "first\n\nthird")
    }

    func testSearchTextMatchesLegacyProjectionAcrossBoundaryCases() {
        let grapheme = "woman technologist: \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        let cases: [[ChatMessage]] = [
            [],
            [ChatMessage(role: .user, content: "")],
            [ChatMessage(role: .user, content: String(repeating: "a", count: 7_999)),
             ChatMessage(role: .assistant, content: "tail")],
            [ChatMessage(role: .user, content: String(repeating: "b", count: 8_000)),
             ChatMessage(role: .assistant, content: "tail")],
            [ChatMessage(role: .user, content: String(repeating: grapheme, count: 1_000)),
             ChatMessage(role: .assistant, content: String(repeating: "finish", count: 2_000))],
        ]

        for messages in cases {
            XCTAssertEqual(searchText(for: messages), legacySearchText(for: messages))
        }
    }

    func testSearchTextStopsAtWholeCharacterLimitBeforeLargeTail() {
        let grapheme = "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"
        let expected = String(repeating: grapheme, count: SidebarItem.maximumSearchTextCharacters)
        let messages = [
            ChatMessage(role: .user, content: expected + grapheme),
            ChatMessage(role: .assistant, content: String(repeating: "unused", count: 1_000_000)),
        ]

        let result = searchText(for: messages)

        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.count, SidebarItem.maximumSearchTextCharacters)
    }

    private func searchText(for messages: [ChatMessage]) -> String {
        SidebarItem(thread: ChatThread(messages: messages)).searchText
    }

    private func legacySearchText(for messages: [ChatMessage]) -> String {
        let combined = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map(\.content)
            .joined(separator: "\n")
        return String(combined.prefix(SidebarItem.maximumSearchTextCharacters))
    }
}
