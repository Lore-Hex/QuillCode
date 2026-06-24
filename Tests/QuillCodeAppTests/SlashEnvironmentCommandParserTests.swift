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
}
