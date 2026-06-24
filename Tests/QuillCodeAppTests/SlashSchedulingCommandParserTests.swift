import XCTest
@testable import QuillCodeApp

final class SlashSchedulingCommandParserTests: XCTestCase {
    func testThreadFollowUpSchedulesTrimmedArgument() {
        XCTAssertEqual(
            SlashSchedulingCommandParser.parseThreadFollowUp("  in 30 minutes  "),
            .threadFollowUp("in 30 minutes")
        )
        XCTAssertEqual(
            SlashSchedulingCommandParser.parseThreadFollowUp("\ndaily\t"),
            .threadFollowUp("daily")
        )
    }

    func testWorkspaceScheduleSchedulesTrimmedArgument() {
        XCTAssertEqual(
            SlashSchedulingCommandParser.parseWorkspaceSchedule("  tomorrow at 9 AM  "),
            .workspaceSchedule("tomorrow at 9 AM")
        )
        XCTAssertEqual(
            SlashSchedulingCommandParser.parseWorkspaceSchedule("\nevery 2 hours\t"),
            .workspaceSchedule("every 2 hours")
        )
    }

    func testEmptySchedulingArgumentsReturnUsageMessages() {
        XCTAssertEqual(
            SlashSchedulingCommandParser.parseThreadFollowUp(" "),
            .invalid("Usage: /follow-up in 30 minutes, /follow-up tomorrow at 9 AM, or /follow-up daily")
        )
        XCTAssertEqual(
            SlashSchedulingCommandParser.parseWorkspaceSchedule("\n\t"),
            .invalid("Usage: /workspace-check in 1 hour, /workspace-check tomorrow at 9 AM, or /workspace-check every 2 hours")
        )
    }

    func testTopLevelSchedulingAliasesDelegateToSchedulingParser() {
        XCTAssertEqual(SlashCommandParser.parse("/followup in 10 minutes"), .threadFollowUp("in 10 minutes"))
        XCTAssertEqual(SlashCommandParser.parse("/schedule tomorrow at 9 AM"), .threadFollowUp("tomorrow at 9 AM"))
        XCTAssertEqual(SlashCommandParser.parse("/remind daily"), .threadFollowUp("daily"))
        XCTAssertEqual(SlashCommandParser.parse("/workspacecheck in 1 hour"), .workspaceSchedule("in 1 hour"))
        XCTAssertEqual(SlashCommandParser.parse("/project-check every 2 hours"), .workspaceSchedule("every 2 hours"))
        XCTAssertEqual(SlashCommandParser.parse("/repo-check tomorrow at 9 AM"), .workspaceSchedule("tomorrow at 9 AM"))
    }
}
