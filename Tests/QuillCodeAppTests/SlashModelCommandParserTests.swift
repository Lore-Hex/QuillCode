import XCTest
@testable import QuillCodeApp

final class SlashModelCommandParserTests: XCTestCase {
    func testModelParsingTrimsModelArgument() {
        XCTAssertEqual(SlashModelCommandParser.parse("  /prometheus  "), .model("/prometheus"))
        XCTAssertEqual(SlashModelCommandParser.parse("\nprovider/model\t"), .model("provider/model"))
    }

    func testEmptyModelReturnsUsageMessage() {
        let expected = SlashCommand.invalid("Usage: /model nike or /model provider/model")

        XCTAssertEqual(SlashModelCommandParser.parse(""), expected)
        XCTAssertEqual(SlashModelCommandParser.parse("   "), expected)
        XCTAssertEqual(SlashCommandParser.parse("/model"), expected)
    }

    func testTopLevelModelCommandDelegatesToModelParser() {
        XCTAssertEqual(SlashCommandParser.parse("/model /prometheus"), .model("/prometheus"))
        XCTAssertEqual(SlashCommandParser.parse("/model trustedrouter/fast"), .model("trustedrouter/fast"))
    }
}
