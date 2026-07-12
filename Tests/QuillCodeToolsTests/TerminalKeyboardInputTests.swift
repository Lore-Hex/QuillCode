import XCTest
@testable import QuillCodeTools

final class TerminalKeyboardInputTests: XCTestCase {
    func testModeParserTracksSplitApplicationCursorAndBracketedPasteSequences() {
        var parser = TerminalKeyboardModeParser()

        parser.consume("plain\u{1B}[?1;20")
        XCTAssertEqual(parser.mode, .standard)
        parser.consume("04hready")
        XCTAssertEqual(
            parser.mode,
            TerminalKeyboardMode(applicationCursorKeys: true, bracketedPaste: true)
        )
        parser.consume("\u{1B}[31mignored\u{1B}[?1l")
        XCTAssertEqual(
            parser.mode,
            TerminalKeyboardMode(applicationCursorKeys: false, bracketedPaste: true)
        )
        parser.reset()
        XCTAssertEqual(parser.mode, .standard)
    }

    func testCursorKeysRespectNormalApplicationAndModifierModes() {
        XCTAssertEqual(encode(.arrowUp), "\u{1B}[A")
        XCTAssertEqual(
            encode(.arrowUp, mode: TerminalKeyboardMode(applicationCursorKeys: true)),
            "\u{1B}OA"
        )
        XCTAssertEqual(
            encode(.arrowLeft, modifiers: .init(shift: true, control: true)),
            "\u{1B}[1;6D"
        )
        XCTAssertEqual(encode(.home), "\u{1B}[H")
        XCTAssertEqual(encode(.end, mode: .init(applicationCursorKeys: true)), "\u{1B}OF")
    }

    func testEditingNavigationFunctionAndControlKeysUseXtermSequences() {
        XCTAssertEqual(encode(.enter), "\r")
        XCTAssertEqual(encode(.tab), "\t")
        XCTAssertEqual(encode(.backtab), "\u{1B}[Z")
        XCTAssertEqual(encode(.escape), "\u{1B}")
        XCTAssertEqual(encode(.backspace), "\u{7F}")
        XCTAssertEqual(encode(.insert), "\u{1B}[2~")
        XCTAssertEqual(encode(.deleteForward, modifiers: .init(control: true)), "\u{1B}[3;5~")
        XCTAssertEqual(encode(.pageUp), "\u{1B}[5~")
        XCTAssertEqual(encode(.pageDown), "\u{1B}[6~")
        XCTAssertEqual(encode(.function(1)), "\u{1B}OP")
        XCTAssertEqual(encode(.function(12), modifiers: .init(shift: true)), "\u{1B}[24;2~")
        XCTAssertNil(encode(.function(13)))
        XCTAssertEqual(encode(.text("c"), modifiers: .init(control: true)), "\u{03}")
        XCTAssertEqual(encode(.text(" "), modifiers: .init(control: true)), "\u{00}")
        XCTAssertEqual(encode(.text("?"), modifiers: .init(control: true)), "\u{7F}")
        XCTAssertEqual(encode(.text("x"), modifiers: .init(option: true)), "\u{1B}x")
    }

    func testBracketedPasteIsBoundedAndCannotInjectItsOwnBoundary() throws {
        let mode = TerminalKeyboardMode(bracketedPaste: true)
        XCTAssertEqual(
            encode(.paste("hello\nworld"), mode: mode),
            "\u{1B}[200~hello\nworld\u{1B}[201~"
        )
        XCTAssertEqual(
            encode(.paste("a\u{1B}[201~b"), mode: mode),
            "\u{1B}[200~ab\u{1B}[201~"
        )
        XCTAssertNil(encode(.paste(""), mode: mode))

        let oversized = String(repeating: "界", count: TerminalKeyboardInputEncoder.maximumPasteUTF8Bytes)
        let encoded = try XCTUnwrap(encode(.paste(oversized)))
        XCTAssertLessThanOrEqual(encoded.utf8.count, TerminalKeyboardInputEncoder.maximumPasteUTF8Bytes)
        XCTAssertTrue(String(data: Data(encoded.utf8), encoding: .utf8) != nil)
    }

    private func encode(
        _ key: TerminalKeyboardKey,
        modifiers: TerminalKeyboardModifiers = TerminalKeyboardModifiers(),
        mode: TerminalKeyboardMode = .standard
    ) -> String? {
        TerminalKeyboardInputEncoder.encode(TerminalKeyboardInputRequest(
            event: TerminalKeyboardInputEvent(key: key, modifiers: modifiers),
            mode: mode
        ))
    }
}
