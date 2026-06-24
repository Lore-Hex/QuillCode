import XCTest
@testable import QuillCodeApp

final class SlashEnvironmentCommandParserTests: XCTestCase {
    func testSupportsEnvironmentAliases() {
        XCTAssertTrue(SlashEnvironmentCommandParser.supports("env"))
        XCTAssertTrue(SlashEnvironmentCommandParser.supports("environment"))
        XCTAssertTrue(SlashEnvironmentCommandParser.supports("local-env"))
        XCTAssertFalse(SlashEnvironmentCommandParser.supports("project"))
    }

    func testEmptyEnvironmentCommandListsActions() {
        XCTAssertEqual(SlashEnvironmentCommandParser.parse(""), .environmentAction(nil))
        XCTAssertEqual(SlashEnvironmentCommandParser.parse("   "), .environmentAction(nil))
        XCTAssertEqual(SlashCommandParser.parse("/env"), .environmentAction(nil))
        XCTAssertEqual(SlashCommandParser.parse("/environment"), .environmentAction(nil))
        XCTAssertEqual(SlashCommandParser.parse("/local-env"), .environmentAction(nil))
    }

    func testEnvironmentActionTrimsQuery() {
        XCTAssertEqual(SlashEnvironmentCommandParser.parse("  Bootstrap  "), .environmentAction("Bootstrap"))
        XCTAssertEqual(SlashCommandParser.parse("/env  Bootstrap  "), .environmentAction("Bootstrap"))
        XCTAssertEqual(SlashCommandParser.parse("/environment test"), .environmentAction("test"))
        XCTAssertEqual(SlashCommandParser.parse("/local-env deploy"), .environmentAction("deploy"))
    }
}
