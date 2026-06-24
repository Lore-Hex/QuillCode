import XCTest
@testable import QuillCodeApp

final class SlashProjectCommandParserTests: XCTestCase {
    func testEmptyProjectCommandReturnsUsageMessage() {
        let expected = SlashCommand.invalid("Usage: /project new, /project refresh, /project rename Name, or /project remove")

        XCTAssertEqual(SlashProjectCommandParser.parse(""), expected)
        XCTAssertEqual(SlashCommandParser.parse("/project"), expected)
    }

    func testProjectNavigationCommandsMapToWorkspaceCommands() {
        XCTAssertEqual(SlashProjectCommandParser.parse("new"), .workspaceCommand("project-new-chat"))
        XCTAssertEqual(SlashProjectCommandParser.parse("new-chat"), .workspaceCommand("project-new-chat"))
        XCTAssertEqual(SlashProjectCommandParser.parse("chat"), .workspaceCommand("project-new-chat"))
        XCTAssertEqual(SlashProjectCommandParser.parse("refresh"), .workspaceCommand("project-refresh-context"))
        XCTAssertEqual(SlashProjectCommandParser.parse("reload"), .workspaceCommand("project-refresh-context"))
        XCTAssertEqual(SlashProjectCommandParser.parse("context"), .workspaceCommand("project-refresh-context"))
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
            .invalid("Unknown project command 'unknown'. Use new, refresh, rename, or remove.")
        )
    }
}
