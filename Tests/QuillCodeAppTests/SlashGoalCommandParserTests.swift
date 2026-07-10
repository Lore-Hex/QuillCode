import XCTest
@testable import QuillCodeApp

final class SlashGoalCommandParserTests: XCTestCase {
    func testParsesGoalLifecycleCommands() {
        XCTAssertEqual(SlashCommandParser.parse("/goal"), .goal(.show))
        XCTAssertEqual(SlashCommandParser.parse("/goal status"), .goal(.show))
        XCTAssertEqual(SlashCommandParser.parse("/goal Ship the release"), .goal(.set("Ship the release")))
        XCTAssertEqual(SlashCommandParser.parse("/goal set Ship the release"), .goal(.set("Ship the release")))
        XCTAssertEqual(SlashCommandParser.parse("/goal complete"), .goal(.complete))
        XCTAssertEqual(SlashCommandParser.parse("/goal block Waiting for CI"), .goal(.block("Waiting for CI")))
        XCTAssertEqual(SlashCommandParser.parse("/goal resume"), .goal(.resume))
        XCTAssertEqual(SlashCommandParser.parse("/goal clear"), .goal(.clear))
    }

    func testRejectsMalformedGoalLifecycleCommands() {
        XCTAssertEqual(SlashCommandParser.parse("/goal set"), .invalid(SlashGoalCommandParser.usage))
        XCTAssertEqual(SlashCommandParser.parse("/goal block"), .invalid(SlashGoalCommandParser.usage))
        XCTAssertEqual(SlashCommandParser.parse("/goal complete extra"), .invalid(SlashGoalCommandParser.usage))
    }
}
