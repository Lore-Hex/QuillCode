import XCTest
@testable import QuillCodeApp

final class SlashRemoteProjectCommandParserTests: XCTestCase {
    func testRemoteProjectParsingTrimsAddress() {
        XCTAssertEqual(
            SlashRemoteProjectCommandParser.parse("  quill@feather:/Quill  "),
            .sshProject("quill@feather:/Quill")
        )
        XCTAssertEqual(
            SlashRemoteProjectCommandParser.parse("\ngenius@quill-feather-001:/home/quill\t"),
            .sshProject("genius@quill-feather-001:/home/quill")
        )
    }

    func testEmptyRemoteProjectReturnsUsageMessage() {
        let expected = SlashCommand.invalid("Usage: /ssh user@host:/absolute/path")

        XCTAssertEqual(SlashRemoteProjectCommandParser.parse(""), expected)
        XCTAssertEqual(SlashRemoteProjectCommandParser.parse("   "), expected)
        XCTAssertEqual(SlashCommandParser.parse("/ssh"), expected)
    }

    func testTopLevelRemoteAliasesDelegateToRemoteProjectParser() {
        XCTAssertEqual(
            SlashCommandParser.parse("/ssh quill@feather:/Quill"),
            .sshProject("quill@feather:/Quill")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/remote  quill@feather:/Quill  "),
            .sshProject("quill@feather:/Quill")
        )
    }
}
