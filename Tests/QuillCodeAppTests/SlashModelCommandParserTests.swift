import XCTest
@testable import QuillCodeApp

final class SlashModelCommandParserTests: XCTestCase {
    func testModelParsingTrimsModelArgument() {
        XCTAssertEqual(SlashModelCommandParser.parse("  /synth  "), .model("/synth"))
        XCTAssertEqual(SlashModelCommandParser.parse("\nprovider/model\t"), .model("provider/model"))
    }

    func testEmptyModelReturnsUsageMessage() {
        let expected = SlashCommand.invalid("Usage: /model /synth or /model provider/model")

        XCTAssertEqual(SlashModelCommandParser.parse(""), expected)
        XCTAssertEqual(SlashModelCommandParser.parse("   "), expected)
        XCTAssertEqual(SlashCommandParser.parse("/model"), expected)
    }

    func testTopLevelModelCommandDelegatesToModelParser() {
        XCTAssertEqual(SlashCommandParser.parse("/model /synth"), .model("/synth"))
        XCTAssertEqual(SlashCommandParser.parse("/model trustedrouter/fast"), .model("trustedrouter/fast"))
    }
}
