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

    // MARK: - Cursor addressing (2D)

    func testCursorPositionOverwritesFromHome() {
        XCTAssertEqual(render("abc\u{1B}[1;1HX"), "Xbc")
        // ESC[H with no params is home (1;1).
        XCTAssertEqual(render("abc\u{1B}[HX"), "Xbc")
    }

    func testCursorPositionToRowAndColumnPadsAsNeeded() {
        // Row 2, column 3 (1-based) -> one empty line above, two leading spaces.
        XCTAssertEqual(render("\u{1B}[2;3HX"), "\n  X")
    }

    func testCursorForwardPadsWithSpaces() {
        XCTAssertEqual(render("ab\u{1B}[CX"), "ab X")
    }

    func testCursorDownPadsRows() {
        XCTAssertEqual(render("a\u{1B}[2BX"), "a\n\n X")
    }

    func testMultiLineProgressRepaintCollapsesToFinalFrame() {
        // Two lines, then move up and rewrite the first — the docker/npm style multi-line update.
        XCTAssertEqual(render("line0\nline1\u{1B}[1A\rNEW0\u{1B}[K"), "NEW0\nline1")
    }

    func testEraseDisplayIsReachableAfterMovingTheCursorHome() {
        // Move home, then erase-to-end-of-screen wipes everything before writing.
        XCTAssertEqual(render("a\nb\u{1B}[1;1H\u{1B}[0JX"), "X")
    }

    func testCursorMovesAreClampedToAvoidUnboundedAllocation() {
        // A hostile/garbled huge move must not pad millions of rows — it clamps (maxRows = 5000).
        let result = render("\u{1B}[9999999BX")
        let lineCount = result.components(separatedBy: "\n").count
        XCTAssertLessThanOrEqual(lineCount, 5001)
        XCTAssertTrue(result.hasSuffix("X"))
        // Same guard for absolute column.
        XCTAssertLessThanOrEqual(render("\u{1B}[9999999GX").count, 5002)
    }

    func testCursorUpAtTopRowClampsToZero() {
        // Cursor up from the first row stays on the first row (no negative index / crash).
        XCTAssertEqual(render("abc\u{1B}[5A\rX"), "Xbc")
    }

    func testNearIntMaxCursorParamsDoNotOverflowTrap() {
        // A param up to Int64.max must be capped BEFORE the cursor arithmetic; otherwise col/row + n
        // overflows and SIGTRAPs the whole process. These crash without the pre-arithmetic cap.
        let intMax = "9223372036854775807"
        XCTAssertEqual(render("X\u{1B}[\(intMax)C"), "X")          // CUF after content
        XCTAssertTrue(render("\n\u{1B}[\(intMax)BX").hasSuffix("X")) // CUD on a non-zero row
        XCTAssertTrue(render("\n\u{1B}[\(intMax)EX").hasSuffix("X")) // CNL on a non-zero row
        XCTAssertTrue(render("ab\u{1B}[\(intMax);\(intMax)Hx").hasSuffix("x")) // CUP both params huge
    }

    func testCursorPositionTreatsZeroParamsAsOne() {
        // ESC[0;0H is defined to mean home (1;1), like ESC[H.
        XCTAssertEqual(render("abc\u{1B}[0;0HX"), "Xbc")
    }

    func testCursorPositionWithEmptyFirstFieldDefaultsToRowOne() {
        // ESC[;5H -> row default 1, column 5.
        XCTAssertEqual(render("\u{1B}[;3HX"), "  X")
    }

    func testEraseStartOfDisplayClearsTheCurrentRowUpToCursor() {
        // ESC[1J must clear rows above AND the current row from its start up to the cursor; the tail
        // after the cursor survives.
        XCTAssertEqual(render("keep\u{1B}[1;3H\u{1B}[1J"), "   p")
    }
}
