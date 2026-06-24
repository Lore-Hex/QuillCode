import XCTest
@testable import QuillCodeApp

final class SlashThreadCommandParserTests: XCTestCase {
    func testThreadLifecycleAliasesMapToCommands() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "new", argument: ""), .newChat)
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "new-chat", argument: ""), .newChat)
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "compact", argument: ""), .workspaceCommand("compact-context"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "duplicate-chat", argument: ""), .workspaceCommand("thread-duplicate"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "archive", argument: ""), .workspaceCommand("thread-archive"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "unarchive-chat", argument: ""), .workspaceCommand("thread-unarchive"))
    }

    func testRenameParsesTrimmedTitleAndUsage() {
        XCTAssertEqual(SlashCommandParser.parse("/rename   Better thread  "), .renameThread("Better thread"))
        XCTAssertEqual(
            SlashThreadCommandParser.parse(name: "rename", argument: ""),
            .invalid("Usage: /rename New chat title")
        )
    }

    func testTopLevelThreadAliasesDelegateToThreadParser() {
        XCTAssertEqual(SlashCommandParser.parse("/new-chat"), .newChat)
        XCTAssertEqual(SlashCommandParser.parse("/context-compact"), .workspaceCommand("compact-context"))
        XCTAssertEqual(SlashCommandParser.parse("/copy-chat"), .workspaceCommand("thread-duplicate"))
        XCTAssertEqual(SlashCommandParser.parse("/archive-chat"), .workspaceCommand("thread-archive"))
        XCTAssertEqual(SlashCommandParser.parse("/unarchive-chat"), .workspaceCommand("thread-unarchive"))
    }

    func testUnknownThreadCommandReturnsNil() {
        XCTAssertNil(SlashThreadCommandParser.parse(name: "help", argument: ""))
    }
}
