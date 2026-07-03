import XCTest
@testable import QuillCodeApp

final class SlashThreadCommandParserTests: XCTestCase {
    func testSupportsThreadLifecycleAliases() {
        [
            "new",
            "new-chat",
            "clear-chat",
            "compact-context",
            "rename-chat",
            "copy-chat",
            "fork",
            "fork-summary",
            "fork-full-context",
            "archive-chat",
            "unarchive-chat",
            "delete-chat"
        ].forEach { XCTAssertTrue(SlashThreadCommandParser.supports($0)) }
        XCTAssertFalse(SlashThreadCommandParser.supports("project"))
    }

    func testNewChatAliasesMapToNewChatCommand() {
        assertThreadParses([
            ("new", "", .newChat),
            ("new-chat", "", .newChat),
            ("newchat", "", .newChat)
        ])
        XCTAssertEqual(SlashCommandParser.parse("/new"), .newChat)
    }

    func testCompactAliasesMapToWorkspaceCommand() {
        assertThreadParses([
            ("compact", "", .workspaceCommand("compact-context")),
            ("compact-context", "", .workspaceCommand("compact-context")),
            ("context-compact", "", .workspaceCommand("compact-context"))
        ])
        XCTAssertEqual(SlashCommandParser.parse("/compact-context"), .workspaceCommand("compact-context"))
    }

    func testClearAliasesMapToThreadClearCommand() {
        assertThreadParses([
            ("clear", "", .workspaceCommand("thread-clear")),
            ("clear-chat", "", .workspaceCommand("thread-clear")),
            ("reset-chat", "", .workspaceCommand("thread-clear"))
        ])
        XCTAssertEqual(SlashCommandParser.parse("/clear"), .workspaceCommand("thread-clear"))
    }

    func testUndoAliasesMapToLatestTurnRevertCommand() {
        assertThreadParses([
            ("undo", "", .workspaceCommand("thread-revert-latest")),
            ("revert", "", .workspaceCommand("thread-revert-latest")),
            ("revert-latest", "", .workspaceCommand("thread-revert-latest")),
            ("undo-edit", "", .workspaceCommand("thread-revert-latest"))
        ])
        XCTAssertEqual(SlashCommandParser.parse("/undo"), .workspaceCommand("thread-revert-latest"))
    }

    func testRenameAliasesTrimTitlesAndValidateRequiredTitle() {
        assertThreadParses([
            ("rename", "  Launch Plan  ", .renameThread("Launch Plan")),
            ("rename-chat", "\nFix CI\t", .renameThread("Fix CI")),
            ("title", "Demo", .renameThread("Demo")),
            ("rename", "   ", .invalid("Usage: /rename New chat title"))
        ])
        XCTAssertEqual(SlashCommandParser.parse("/rename  Better UX  "), .renameThread("Better UX"))
    }

    func testDuplicatePinArchiveUnarchiveAndDeleteAliasesMapToWorkspaceCommands() {
        assertThreadParses([
            ("duplicate", "", .workspaceCommand("thread-duplicate")),
            ("copy-chat", "", .workspaceCommand("thread-duplicate")),
            ("pin", "", .workspaceCommand("thread-pin")),
            ("pin-chat", "", .workspaceCommand("thread-pin")),
            ("unpin", "", .workspaceCommand("thread-unpin")),
            ("unpin-chat", "", .workspaceCommand("thread-unpin")),
            ("archive", "", .workspaceCommand("thread-archive")),
            ("archive-chat", "", .workspaceCommand("thread-archive")),
            ("unarchive", "", .workspaceCommand("thread-unarchive")),
            ("unarchive-chat", "", .workspaceCommand("thread-unarchive")),
            ("delete", "", .workspaceCommand("thread-delete")),
            ("delete-chat", "", .workspaceCommand("thread-delete")),
            ("remove-chat", "", .workspaceCommand("thread-delete"))
        ])
        assertTopLevelParses([
            ("/duplicate-chat", .workspaceCommand("thread-duplicate")),
            ("/pin", .workspaceCommand("thread-pin")),
            ("/unpin-chat", .workspaceCommand("thread-unpin")),
            ("/delete-chat", .workspaceCommand("thread-delete"))
        ])
    }

    func testForkAliasesAndModesMapToWorkspaceCommands() {
        assertThreadParses([
            ("fork", "", .workspaceCommand("fork-from-last")),
            ("fork", " latest ", .workspaceCommand("fork-from-last")),
            ("fork", "summary", .workspaceCommand("fork-with-summary")),
            ("fork", "compact", .workspaceCommand("fork-with-summary")),
            ("fork", "full", .workspaceCommand("fork-full-context")),
            ("fork", "all", .workspaceCommand("fork-full-context")),
            ("fork-last", "", .workspaceCommand("fork-from-last")),
            ("fork-summary", "", .workspaceCommand("fork-with-summary")),
            ("fork-full-context", "", .workspaceCommand("fork-full-context")),
            ("fork", "banana", .invalid("Usage: /fork [last|summary|full]"))
        ])
        assertTopLevelParses([
            ("/fork summary", .workspaceCommand("fork-with-summary")),
            ("/fork-full", .workspaceCommand("fork-full-context"))
        ])
    }

    private func assertThreadParses(
        _ cases: [(name: String, argument: String, expected: SlashCommand)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for testCase in cases {
            XCTAssertEqual(
                SlashThreadCommandParser.parse(name: testCase.name, argument: testCase.argument),
                testCase.expected,
                file: file,
                line: line
            )
        }
    }

    private func assertTopLevelParses(
        _ cases: [(input: String, expected: SlashCommand)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for testCase in cases {
            XCTAssertEqual(
                SlashCommandParser.parse(testCase.input),
                testCase.expected,
                file: file,
                line: line
            )
        }
    }
}
