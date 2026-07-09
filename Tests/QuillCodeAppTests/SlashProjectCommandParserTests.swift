import XCTest
@testable import QuillCodeApp

final class SlashProjectCommandParserTests: XCTestCase {
    func testEmptyProjectCommandReturnsUsageMessage() {
        let expected = SlashCommand.invalid(
            """
            Usage: /project open, /project new, /project refresh, /project top, /project up, \
            /project down, /project rename Name, or /project remove
            """
        )

        XCTAssertEqual(SlashProjectCommandParser.parse(""), expected)
        XCTAssertEqual(SlashCommandParser.parse("/project"), expected)
    }

    func testProjectNavigationCommandsMapToWorkspaceCommands() {
        XCTAssertEqual(SlashProjectCommandParser.parse("open"), .workspaceCommand("add-project"))
        XCTAssertEqual(SlashProjectCommandParser.parse("add"), .workspaceCommand("add-project"))
        XCTAssertEqual(SlashCommandParser.parse("/project open"), .workspaceCommand("add-project"))
        XCTAssertEqual(SlashProjectCommandParser.parse("new"), .workspaceCommand("project-new-chat"))
        XCTAssertEqual(SlashProjectCommandParser.parse("new-chat"), .workspaceCommand("project-new-chat"))
        XCTAssertEqual(SlashProjectCommandParser.parse("chat"), .workspaceCommand("project-new-chat"))
        XCTAssertEqual(SlashProjectCommandParser.parse("refresh"), .workspaceCommand("project-refresh-context"))
        XCTAssertEqual(SlashProjectCommandParser.parse("reload"), .workspaceCommand("project-refresh-context"))
        XCTAssertEqual(SlashProjectCommandParser.parse("context"), .workspaceCommand("project-refresh-context"))
        XCTAssertEqual(SlashProjectCommandParser.parse("top"), .workspaceCommand("project-move-to-top"))
        XCTAssertEqual(SlashProjectCommandParser.parse("move-top"), .workspaceCommand("project-move-to-top"))
        XCTAssertEqual(SlashProjectCommandParser.parse("up"), .workspaceCommand("project-move-up"))
        XCTAssertEqual(SlashProjectCommandParser.parse("move-up"), .workspaceCommand("project-move-up"))
        XCTAssertEqual(SlashProjectCommandParser.parse("down"), .workspaceCommand("project-move-down"))
        XCTAssertEqual(SlashProjectCommandParser.parse("move-down"), .workspaceCommand("project-move-down"))
        XCTAssertEqual(SlashProjectCommandParser.parse("remove"), .workspaceCommand("project-remove"))
        XCTAssertEqual(SlashProjectCommandParser.parse("forget"), .workspaceCommand("project-remove"))
        XCTAssertEqual(SlashProjectCommandParser.parse("delete"), .workspaceCommand("project-remove"))
    }

    func testProjectRenameCommandsTrimNames() {
        XCTAssertEqual(SlashProjectCommandParser.parse("rename QuillCode"), .renameProject("QuillCode"))
        XCTAssertEqual(SlashProjectCommandParser.parse("title   Quill Code  "), .renameProject("Quill Code"))
        XCTAssertEqual(SlashCommandParser.parse("/project rename  Shippable App  "), .renameProject("Shippable App"))
    }

    func testInvalidProjectSubcommandsReturnUsageMessages() {
        XCTAssertEqual(
            SlashProjectCommandParser.parse("rename"),
            .invalid("Usage: /project rename Project name")
        )
        XCTAssertEqual(
            SlashProjectCommandParser.parse("unknown"),
            .invalid("Unknown project command 'unknown'. Use open, new, refresh, top, up, down, rename, or remove.")
        )
    }
}
