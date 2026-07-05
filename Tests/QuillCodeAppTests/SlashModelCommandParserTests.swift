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

    func testRetiredRawModelNamesAreRejected() {
        let expected = SlashCommand.invalid(
            "The raw synth model type is no longer a named endpoint. Use /model nike, /model prometheus, or a provider/model from TrustedRouter."
        )

        XCTAssertEqual(SlashModelCommandParser.parse("synth"), expected)
        XCTAssertEqual(SlashCommandParser.parse("/model tr/synth"), expected)
    }

    func testTopLevelModelCommandDelegatesToModelParser() {
        XCTAssertEqual(SlashCommandParser.parse("/model /prometheus"), .model("/prometheus"))
        XCTAssertEqual(SlashCommandParser.parse("/model trustedrouter/fast"), .model("trustedrouter/fast"))
    }
}
