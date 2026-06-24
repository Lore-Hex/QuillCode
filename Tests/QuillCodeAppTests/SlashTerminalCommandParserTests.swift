import XCTest
@testable import QuillCodeApp

final class SlashTerminalCommandParserTests: XCTestCase {
    func testTerminalToggleAliasesMapToWorkspaceCommand() {
        XCTAssertEqual(SlashTerminalCommandParser.parse(""), .workspaceCommand("toggle-terminal"))
        XCTAssertEqual(SlashTerminalCommandParser.parse("   "), .workspaceCommand("toggle-terminal"))
        XCTAssertEqual(SlashCommandParser.parse("/terminal"), .workspaceCommand("toggle-terminal"))
        XCTAssertEqual(SlashCommandParser.parse("/term"), .workspaceCommand("toggle-terminal"))
        XCTAssertEqual(SlashCommandParser.parse("/shell"), .workspaceCommand("toggle-terminal"))
    }

    func testTerminalClearAliasesMapToWorkspaceCommand() {
        XCTAssertEqual(SlashTerminalCommandParser.parse("clear"), .workspaceCommand("terminal-clear"))
        XCTAssertEqual(SlashTerminalCommandParser.parse("reset"), .workspaceCommand("terminal-clear"))
        XCTAssertEqual(SlashTerminalCommandParser.parse(" CLEAR "), .workspaceCommand("terminal-clear"))
        XCTAssertEqual(SlashCommandParser.parse("/terminal clear"), .workspaceCommand("terminal-clear"))
        XCTAssertEqual(SlashCommandParser.parse("/term reset"), .workspaceCommand("terminal-clear"))
        XCTAssertEqual(SlashCommandParser.parse("/shell clear"), .workspaceCommand("terminal-clear"))
    }

    func testInvalidTerminalSubcommandsReturnUsageMessage() {
        XCTAssertEqual(
            SlashTerminalCommandParser.parse("status"),
            .invalid("Usage: /terminal or /terminal clear")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/terminal status"),
            .invalid("Usage: /terminal or /terminal clear")
        )
    }
}
