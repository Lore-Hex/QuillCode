import XCTest
@testable import QuillCodeApp

final class SlashEnvironmentCommandParserTests: XCTestCase {
    func testSupportsEnvironmentAliases() {
        XCTAssertTrue(SlashEnvironmentCommandParser.supports("env"))
        XCTAssertTrue(SlashEnvironmentCommandParser.supports("environment"))
        XCTAssertTrue(SlashEnvironmentCommandParser.supports("local-env"))
        XCTAssertFalse(SlashEnvironmentCommandParser.supports("project"))
    }

    func testEmptyEnvironmentArgumentListsActions() {
        XCTAssertEqual(SlashEnvironmentCommandParser.parse(""), .environmentAction(nil))
        XCTAssertEqual(SlashEnvironmentCommandParser.parse(" \n\t "), .environmentAction(nil))
        XCTAssertEqual(SlashCommandParser.parse("/env"), .environmentAction(nil))
        XCTAssertEqual(SlashCommandParser.parse("/environment"), .environmentAction(nil))
        XCTAssertEqual(SlashCommandParser.parse("/local-env"), .environmentAction(nil))
    }

    func testEnvironmentActionQueryIsTrimmed() {
        XCTAssertEqual(SlashEnvironmentCommandParser.parse("  bootstrap env  "), .environmentAction("bootstrap env"))
        XCTAssertEqual(SlashCommandParser.parse("/env   prepare workspace  "), .environmentAction("prepare workspace"))
        XCTAssertEqual(SlashCommandParser.parse("/local-env \n smoke\t"), .environmentAction("smoke"))
    }

    func testEnvironmentScheduleIsParsedSeparatelyFromImmediateAction() {
        XCTAssertEqual(
            SlashEnvironmentCommandParser.parse("schedule Verify in 30 minutes"),
            .environmentSchedule("Verify in 30 minutes")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/local-env schedule Build every 2 hours"),
            .environmentSchedule("Build every 2 hours")
        )
        XCTAssertEqual(
            SlashEnvironmentCommandParser.parse("SCHEDULE\tVerify Workspace tomorrow"),
            .environmentSchedule("Verify Workspace tomorrow")
        )
        XCTAssertEqual(
            SlashEnvironmentCommandParser.parse("schedule   "),
            .invalid("Usage: /env schedule Action name in 30 minutes")
        )
    }
}
