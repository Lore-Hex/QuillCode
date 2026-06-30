import XCTest
@testable import QuillCodeTools

final class TerminalOutputRendererTests: XCTestCase {
    private func render(_ raw: String) -> String { TerminalOutputRenderer.render(raw) }

    func testPlainTextPassesThroughUnchanged() {
        XCTAssertEqual(render("hello world\nsecond line"), "hello world\nsecond line")
        XCTAssertEqual(render(""), "")
    }

    func testStripsSGRColorAndStyleCodes() {
        XCTAssertEqual(render("\u{1B}[31mred\u{1B}[0m"), "red")
        XCTAssertEqual(render("\u{1B}[1;32mbold green\u{1B}[0m done"), "bold green done")
    }

    func testCarriageReturnOverwritesFromColumnZero() {
        XCTAssertEqual(render("abc\rXYZ"), "XYZ")
        // A shorter overwrite leaves the tail of the original line in place.
        XCTAssertEqual(render("abcdef\rXYZ"), "XYZdef")
    }

    func testBackspaceMovesTheCursorBack() {
        XCTAssertEqual(render("abc\u{08}\u{08}X"), "aXc")
    }

    func testEraseLineToEnd() {
        // \r returns to column 0, X overwrites 'a', ESC[K erases the rest of the line.
        XCTAssertEqual(render("abc\rX\u{1B}[K"), "X")
    }

    func testEraseWholeLineKeepsCursorColumn() {
        // ESC[2K clears the line but not the cursor column; ESC[H-style moves are out of scope, so a
        // \r is the realistic way to reset before rewriting.
        XCTAssertEqual(render("abc\r\u{1B}[2Kdef"), "def")
    }

    func testEraseDisplayResetsTheBuffer() {
        XCTAssertEqual(render("old output\u{1B}[2Jfresh"), "fresh")
    }

    func testRealisticColoredProgressBarCollapsesToFinalState() {
        let raw = "\u{1B}[32m[####    ] 50%\r[######  ] 75%\u{1B}[0m"
        XCTAssertEqual(render(raw), "[######  ] 75%")
    }

    func testStripsBellAndOSCTitleSequences() {
        XCTAssertEqual(render("ding\u{07}dong"), "dingdong")
        // OSC set-title terminated by BEL.
        XCTAssertEqual(render("\u{1B}]0;my title\u{07}prompt$ "), "prompt$ ")
    }

    func testDropsIncompleteTrailingEscapeSequences() {
        // A sequence split across stream chunks: the partial tail must not render as literal text.
        XCTAssertEqual(render("text\u{1B}["), "text")
        XCTAssertEqual(render("text\u{1B}"), "text")
        XCTAssertEqual(render("text\u{1B}[31"), "text")
    }

    func testPreservesUnicodeContent() {
        XCTAssertEqual(render("caf\u{00E9} \u{2014} \u{1F680}"), "caf\u{00E9} \u{2014} \u{1F680}")
        XCTAssertEqual(render("\u{1B}[33m\u{2713} ok\u{1B}[0m"), "\u{2713} ok")
    }

    func testIsIdempotentOnCleanText() {
        let once = render("\u{1B}[31mred\u{1B}[0m\r\u{1B}[Kdone")
        XCTAssertEqual(render(once), once)
    }

    func testStripsCharsetDesignationSequences() {
        // ESC ( B / ESC ) 0 are 3-byte sequences; the final byte must not leak as a stray char.
        XCTAssertEqual(render("a\u{1B}(Bb"), "ab")
        XCTAssertEqual(render("a\u{1B})0b"), "ab")
        // The exact `tput sgr0` reset (`ESC ( B` + `ESC [ m`) that colored CLIs emit.
        XCTAssertEqual(render("x\u{1B}(B\u{1B}[my"), "xy")
    }

    func testDoubleEscapeRestartsInsteadOfLeakingTheFollowingSequence() {
        // ESC ESC must cancel-and-restart: the second ESC begins a fresh CSI that is stripped, rather
        // than the first ESC swallowing the second and leaking `[31m` as literal text.
        XCTAssertEqual(render("a\u{1B}\u{1B}[31mb"), "ab")
    }

    func testEscapeFollowedByControlDoesNotSwallowTheControl() {
        // A stray ESC before a newline must not eat the newline.
        XCTAssertEqual(render("a\u{1B}\nb"), "a\nb")
    }

    func testStripsPrivateModeCSISequences() {
        // Cursor hide/show (ESC[?25l / ESC[?25h) — params include `?`; must strip cleanly, not leak.
        XCTAssertEqual(render("\u{1B}[?25lwork\u{1B}[?25h"), "work")
    }

    func testIncompleteSequenceRendersCorrectlyOnceTheBufferGrows() {
        // A sequence split across stream chunks: the partial render drops the tail, and the render of
        // the grown buffer (with the completion) produces the correct result — no literal leak.
        XCTAssertEqual(render("text\u{1B}[31"), "text")
        XCTAssertEqual(render("text\u{1B}[31mred"), "textred")
    }
}
