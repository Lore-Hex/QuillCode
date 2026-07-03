import XCTest
@testable import QuillCodeApp

final class SlashThreadCommandParserTests: XCTestCase {
    func testSupportsThreadLifecycleAliases() {
        XCTAssertTrue(SlashThreadCommandParser.supports("new"))
        XCTAssertTrue(SlashThreadCommandParser.supports("new-chat"))
        XCTAssertTrue(SlashThreadCommandParser.supports("clear-chat"))
        XCTAssertTrue(SlashThreadCommandParser.supports("compact-context"))
        XCTAssertTrue(SlashThreadCommandParser.supports("rename-chat"))
        XCTAssertTrue(SlashThreadCommandParser.supports("copy-chat"))
        XCTAssertTrue(SlashThreadCommandParser.supports("archive-chat"))
        XCTAssertTrue(SlashThreadCommandParser.supports("unarchive-chat"))
        XCTAssertTrue(SlashThreadCommandParser.supports("delete-chat"))
        XCTAssertFalse(SlashThreadCommandParser.supports("project"))
    }

    func testNewChatAliasesMapToNewChatCommand() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "new", argument: ""), .newChat)
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "new-chat", argument: ""), .newChat)
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "newchat", argument: ""), .newChat)
        XCTAssertEqual(SlashCommandParser.parse("/new"), .newChat)
    }

    func testCompactAliasesMapToWorkspaceCommand() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "compact", argument: ""), .workspaceCommand("compact-context"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "compact-context", argument: ""), .workspaceCommand("compact-context"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "context-compact", argument: ""), .workspaceCommand("compact-context"))
        XCTAssertEqual(SlashCommandParser.parse("/compact-context"), .workspaceCommand("compact-context"))
    }

    func testClearAliasesMapToThreadClearCommand() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "clear", argument: ""), .workspaceCommand("thread-clear"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "clear-chat", argument: ""), .workspaceCommand("thread-clear"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "reset-chat", argument: ""), .workspaceCommand("thread-clear"))
        XCTAssertEqual(SlashCommandParser.parse("/clear"), .workspaceCommand("thread-clear"))
    }

    func testUndoAliasesMapToLatestTurnRevertCommand() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "undo", argument: ""), .workspaceCommand("thread-revert-latest"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "revert", argument: ""), .workspaceCommand("thread-revert-latest"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "revert-latest", argument: ""), .workspaceCommand("thread-revert-latest"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "undo-edit", argument: ""), .workspaceCommand("thread-revert-latest"))
        XCTAssertEqual(SlashCommandParser.parse("/undo"), .workspaceCommand("thread-revert-latest"))
    }

    func testRenameAliasesTrimTitlesAndValidateRequiredTitle() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "rename", argument: "  Launch Plan  "), .renameThread("Launch Plan"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "rename-chat", argument: "\nFix CI\t"), .renameThread("Fix CI"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "title", argument: "Demo"), .renameThread("Demo"))
        XCTAssertEqual(SlashCommandParser.parse("/rename  Better UX  "), .renameThread("Better UX"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "rename", argument: "   "), .invalid("Usage: /rename New chat title"))
    }

    func testDuplicatePinArchiveUnarchiveAndDeleteAliasesMapToWorkspaceCommands() {
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "duplicate", argument: ""), .workspaceCommand("thread-duplicate"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "copy-chat", argument: ""), .workspaceCommand("thread-duplicate"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "pin", argument: ""), .workspaceCommand("thread-pin"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "pin-chat", argument: ""), .workspaceCommand("thread-pin"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "unpin", argument: ""), .workspaceCommand("thread-unpin"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "unpin-chat", argument: ""), .workspaceCommand("thread-unpin"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "archive", argument: ""), .workspaceCommand("thread-archive"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "archive-chat", argument: ""), .workspaceCommand("thread-archive"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "unarchive", argument: ""), .workspaceCommand("thread-unarchive"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "unarchive-chat", argument: ""), .workspaceCommand("thread-unarchive"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "delete", argument: ""), .workspaceCommand("thread-delete"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "delete-chat", argument: ""), .workspaceCommand("thread-delete"))
        XCTAssertEqual(SlashThreadCommandParser.parse(name: "remove-chat", argument: ""), .workspaceCommand("thread-delete"))
        XCTAssertEqual(SlashCommandParser.parse("/duplicate-chat"), .workspaceCommand("thread-duplicate"))
        XCTAssertEqual(SlashCommandParser.parse("/pin"), .workspaceCommand("thread-pin"))
        XCTAssertEqual(SlashCommandParser.parse("/unpin-chat"), .workspaceCommand("thread-unpin"))
        XCTAssertEqual(SlashCommandParser.parse("/delete-chat"), .workspaceCommand("thread-delete"))
    }
}
