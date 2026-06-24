import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class SlashModeCommandParserTests: XCTestCase {
    func testModeAliasesMapToAgentModes() {
        XCTAssertEqual(SlashModeCommandParser.parse("auto"), .mode(.auto))
        XCTAssertEqual(SlashModeCommandParser.parse("review"), .mode(.review))
        XCTAssertEqual(SlashModeCommandParser.parse("read-only"), .mode(.readOnly))
        XCTAssertEqual(SlashModeCommandParser.parse("readonly"), .mode(.readOnly))
        XCTAssertEqual(SlashModeCommandParser.parse("read_only"), .mode(.readOnly))
    }

    func testModeParsingIsCaseAndWhitespaceTolerant() {
        XCTAssertEqual(SlashModeCommandParser.parse(" AUTO "), .mode(.auto))
        XCTAssertEqual(SlashModeCommandParser.parse("\nReview\t"), .mode(.review))
        XCTAssertEqual(SlashCommandParser.parse("/mode READ_ONLY"), .mode(.readOnly))
    }

    func testEmptyModeReturnsUsageMessage() {
        let expected = SlashCommand.invalid("Usage: /mode auto, /mode review, or /mode read-only")

        XCTAssertEqual(SlashModeCommandParser.parse(""), expected)
        XCTAssertEqual(SlashModeCommandParser.parse("   "), expected)
        XCTAssertEqual(SlashCommandParser.parse("/mode"), expected)
    }

    func testUnknownModeReturnsTrimmedArgumentInError() {
        XCTAssertEqual(
            SlashModeCommandParser.parse("  full-access  "),
            .invalid("Unknown mode 'full-access'. Use auto, review, or read-only.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/mode full-access"),
            .invalid("Unknown mode 'full-access'. Use auto, review, or read-only.")
        )
    }
}
