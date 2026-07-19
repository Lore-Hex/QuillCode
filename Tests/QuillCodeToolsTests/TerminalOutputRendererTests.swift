import XCTest
@testable import QuillCodeTools

final class TerminalOutputRendererTests: XCTestCase {
    private func render(
        _ raw: String,
        ambiguousWidthPolicy: TerminalOutputAmbiguousWidthPolicy = .narrow
    ) -> String {
        TerminalOutputRenderer.render(raw, ambiguousWidthPolicy: ambiguousWidthPolicy)
    }

    func testPlainTextPassesThroughUnchanged() {
        XCTAssertEqual(render("hello world\nsecond line"), "hello world\nsecond line")
        XCTAssertEqual(render(""), "")
    }

    func testStripsSGRColorAndStyleCodes() {
        XCTAssertEqual(render("\u{1B}[31mred\u{1B}[0m"), "red")
        XCTAssertEqual(render("\u{1B}[1;32mbold green\u{1B}[0m done"), "bold green done")
    }

    func testC1CSISequencesShareTheNormalCSIParser() {
        XCTAssertEqual(render("\u{9B}31mred\u{9B}0m"), "red")
        XCTAssertEqual(render("abc\u{9B}1;2HXY"), "aXY")
    }

    func testRISResetClearsScreenCursorStyleAndModes() {
        let raw = "old"
            + "\u{1B}[31m"
            + "\u{1B}[?1000h"
            + "\u{1B}[2;3r"
            + "\u{1B}7"
            + "\u{1B}c"
            + "new"
        let frame = TerminalOutputRenderer.renderFrame(raw)

        XCTAssertEqual(frame.text, "new")
        XCTAssertEqual(frame.runs, [TerminalTextRun(text: "new")])
        XCTAssertEqual(frame.mouseReporting, .disabled)
    }

    func testRISResetDropsAlternateScreenSnapshot() {
        let raw = "main"
            + "\u{1B}[?1049h"
            + "alternate"
            + "\u{1B}c"
            + "after"
            + "\u{1B}[?1049l"

        XCTAssertEqual(render(raw), "after")
    }

    func testSoftResetPreservesScreenButResetsStyleModesAndTabs() {
        let raw = "\u{1B}[3g"
            + "\u{1B}[?1000;1006h"
            + "\u{1B}[31mred"
            + "\u{1B}[!p"
            + " plain"
            + "\r\u{1B}[2K"
            + "X\tY"
        let frame = TerminalOutputRenderer.renderFrame(raw)

        XCTAssertEqual(frame.text, "X       Y")
        XCTAssertEqual(frame.mouseReporting, .disabled)
        XCTAssertEqual(frame.runs, [TerminalTextRun(text: "X       Y")])
    }

    func testScreenAlignmentPatternFillsFallbackViewport() {
        let frame = TerminalOutputRenderer.renderFrame("old\u{1B}#8")
        let lines = frame.text.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.allSatisfy { $0 == String(repeating: "E", count: 80) })
    }

    func testScreenAlignmentPatternPreservesCurrentStyleAndHomesCursor() {
        let raw = "\u{1B}[32m"
            + "\u{1B}#8"
            + "\u{1B}[0m"
            + "X"
        let frame = TerminalOutputRenderer.renderFrame(raw)

        XCTAssertTrue(frame.text.hasPrefix("X" + String(repeating: "E", count: 79)))
        XCTAssertEqual(frame.runs.first?.text, "X")
        XCTAssertEqual(frame.runs.first?.style, .plain)
        XCTAssertEqual(frame.runs.dropFirst().first?.text.prefix(3), "EEE")
        XCTAssertEqual(frame.runs.dropFirst().first?.style.foreground, .green)
    }

    func testPreservesSGRColorsAndEmphasisAsStyledRuns() {
        let frame = TerminalOutputRenderer.renderFrame(
            "plain \u{1B}[1;3;4;31;44mstyled\u{1B}[22;23;24;39;49m done"
        )

        XCTAssertEqual(frame.text, "plain styled done")
        XCTAssertEqual(frame.runs.count, 3)
        XCTAssertEqual(frame.runs[0], TerminalTextRun(text: "plain "))
        XCTAssertEqual(frame.runs[1].text, "styled")
        XCTAssertEqual(frame.runs[1].style.foreground, .red)
        XCTAssertEqual(frame.runs[1].style.background, .blue)
        XCTAssertTrue(frame.runs[1].style.isBold)
        XCTAssertTrue(frame.runs[1].style.isItalic)
        XCTAssertTrue(frame.runs[1].style.isUnderlined)
        XCTAssertEqual(frame.runs[2], TerminalTextRun(text: " done"))
    }

    func testPreservesExtendedIndexedRGBInverseAndStrikethroughStyles() {
        let frame = TerminalOutputRenderer.renderFrame(
            "\u{1B}[38;5;202;48;2;1;2;3;7;9mvalue\u{1B}[0m"
        )

        XCTAssertEqual(frame.runs.count, 1)
        let style = frame.runs[0].style
        XCTAssertEqual(style.foreground, .indexed(202))
        XCTAssertEqual(style.background, .rgb(TerminalRGBColor(red: 1, green: 2, blue: 3)))
        XCTAssertTrue(style.isInverse)
        XCTAssertTrue(style.isStrikethrough)
    }

    func testSupportsColonFormRGBAndUnderlineReset() {
        let frame = TerminalOutputRenderer.renderFrame(
            "\u{1B}[38:2::12:34:56;4:2munder\u{1B}[4:0m plain"
        )

        XCTAssertEqual(frame.text, "under plain")
        XCTAssertEqual(
            frame.runs[0].style.foreground,
            .rgb(TerminalRGBColor(red: 12, green: 34, blue: 56))
        )
        XCTAssertTrue(frame.runs[0].style.isUnderlined)
        XCTAssertFalse(frame.runs[1].style.isUnderlined)
    }

    func testIndexedColorPaletteResolvesStandardCubeAndGrayEntries() {
        XCTAssertEqual(TerminalTextColor.indexed(1).resolvedRGB, .init(red: 205, green: 0, blue: 0))
        XCTAssertEqual(TerminalTextColor.indexed(16).resolvedRGB, .init(red: 0, green: 0, blue: 0))
        XCTAssertEqual(TerminalTextColor.indexed(21).resolvedRGB, .init(red: 0, green: 0, blue: 255))
        XCTAssertEqual(TerminalTextColor.indexed(232).resolvedRGB, .init(red: 8, green: 8, blue: 8))
        XCTAssertEqual(TerminalTextColor.indexed(255).resolvedRGB, .init(red: 238, green: 238, blue: 238))
    }

    func testAlternateScreenPreservesStyledLatestFrame() {
        let frame = TerminalOutputRenderer.renderFrame(
            "before\n\u{1B}[?1049h\u{1B}[32mALT\nFRAME\u{1B}[0m\u{1B}[?1049l after"
        )

        XCTAssertEqual(frame.text, "before\nALT\nFRAME after")
        XCTAssertEqual(frame.runs.first(where: { $0.text.contains("ALT") })?.style.foreground, .green)
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

    func testCursorHomeRedrawsExistingScreen() {
        let raw = "cpu: 10%\nmem: 20%\u{1B}[Hcpu: 90%"

        XCTAssertEqual(render(raw), "cpu: 90%\nmem: 20%")
    }

    func testCursorAddressedTUIRedrawUpdatesSpecificCells() {
        let raw = [
            "Name: old",
            "Status: wait"
        ].joined(separator: "\n")
            + "\u{1B}[1;7Hnew"
            + "\u{1B}[2;9Hdone"

        XCTAssertEqual(render(raw), "Name: new\nStatus: done")
    }

    func testRelativeCursorMovementUpdatesPriorRows() {
        let raw = "A1\nB1\nC1"
            + "\u{1B}[1A\u{1B}[2G2"
            + "\u{1B}[1B\u{1B}[2G2"

        XCTAssertEqual(render(raw), "A1\nB2\nC2")
    }

    func testRelativePositionAliasesMoveCursorRightAndDown() {
        XCTAssertEqual(render("A\u{1B}[3aZ"), "A   Z")
        XCTAssertEqual(render("top\u{1B}[2eX"), "top\n\n   X")
    }

    func testCursorForwardPadsWhenWritingPastEndOfLine() {
        XCTAssertEqual(render("x\u{1B}[5Gz"), "x   z")
    }

    func testHorizontalTabAdvancesToFixedTabStop() {
        XCTAssertEqual(render("a\tX"), "a       X")
        XCTAssertEqual(render("abcdefgh\tX"), "abcdefgh        X")
    }

    func testCSIForwardAndBackwardTabMoveByFixedTabStops() {
        XCTAssertEqual(render("a\u{1B}[IX"), "a       X")
        XCTAssertEqual(render("\u{1B}[2IX"), "                X")
        XCTAssertEqual(render("abcdefghi\u{1B}[ZX"), "abcdefghX")
        XCTAssertEqual(render("abcdefghi\u{1B}[2ZX"), "Xbcdefghi")
    }

    func testHorizontalTabStopEscapeSetsCustomStop() {
        let raw = "\u{1B}[4G"
            + "\u{1B}H"
            + "\r"
            + "X\tY"

        XCTAssertEqual(render(raw), "X  Y")
    }

    func testHorizontalTabStopClearRemovesCurrentStop() {
        let raw = "\u{1B}[4G"
            + "\u{1B}H"
            + "\u{1B}[g"
            + "\r"
            + "X\tY"

        XCTAssertEqual(render(raw), "X       Y")
    }

    func testHorizontalTabStopClearAllLeavesTabsAtRightBoundary() {
        let raw = "\u{1B}[3gX\tY"
        let output = render(raw)

        XCTAssertEqual(output.count, 1_001)
        XCTAssertEqual(output.first, "X")
        XCTAssertEqual(output.last, "Y")
    }

    func testBackwardTabUsesCustomStops() {
        let raw = "\u{1B}[3g"
            + "abcd"
            + "\u{1B}H"
            + "\u{1B}[12G"
            + "Z"
            + "\u{1B}[Z"
            + "Y"

        XCTAssertEqual(render(raw), "abcdY      Z")
    }

    func testRISResetRestoresDefaultTabStops() {
        let raw = "\u{1B}[3g"
            + "\u{1B}c"
            + "X\tY"

        XCTAssertEqual(render(raw), "X       Y")
    }

    func testCursorAddressingIsBoundedForSparseHugeMoves() {
        let output = render("x\u{1B}[2000;2000Hz")
        let lines = output.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 1_001)
        XCTAssertEqual(lines.last?.count, 1_001)
        XCTAssertEqual(lines.last?.last, "z")
    }

    func testCursorSaveAndRestoreSupportsAnsiAndDECForms() {
        XCTAssertEqual(render("abc\u{1B}[sXYZ\u{1B}[u!"), "abc!YZ")
        XCTAssertEqual(render("abc\u{1B}7XYZ\u{1B}8!"), "abc!YZ")
    }

    func testEraseDisplayToStartBlanksCurrentPrefix() {
        XCTAssertEqual(render("alpha\nbravo\u{1B}[2;3H\u{1B}[1JX"), "\n  Xvo")
    }

    func testRealisticColoredProgressBarCollapsesToFinalState() {
        let raw = "\u{1B}[32m[####    ] 50%\r[######  ] 75%\u{1B}[0m"
        XCTAssertEqual(render(raw), "[######  ] 75%")
    }

    func testSimpleFullScreenTUIRefreshCollapsesToLatestFrame() {
        let firstFrame = [
            "PID CPU MEM",
            "101  1  2",
            "102  3  4"
        ].joined(separator: "\n")
        let secondFrame = "\u{1B}[H"
            + "PID CPU MEM"
            + "\u{1B}[2;6H9"
            + "\u{1B}[3;6H8"

        XCTAssertEqual(render(firstFrame + secondFrame), "PID CPU MEM\n101  9  2\n102  8  4")
    }

    func testScrollRegionLineFeedScrollsOnlyTheRegion() {
        let raw = [
            "header",
            "row1",
            "row2",
            "footer"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[3;1H"
            + "\nnew"

        XCTAssertEqual(render(raw), "header\nrow2\nnew\nfooter")
    }

    func testOriginModeAddressesRowsRelativeToScrollRegion() {
        let raw = [
            "top",
            "middle",
            "bottom"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[?6h"
            + "\u{1B}[1;1HX"

        XCTAssertEqual(render(raw), "top\nXiddle\nbottom")
    }

    func testOriginModeResetRestoresAbsoluteAddressing() {
        let raw = [
            "top",
            "middle",
            "bottom"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[?6h"
            + "\u{1B}[?6l"
            + "\u{1B}[1;1HX"

        XCTAssertEqual(render(raw), "Xop\nmiddle\nbottom")
    }

    func testVerticalPositionAbsoluteHonorsOriginMode() {
        let raw = [
            "top",
            "middle",
            "bottom"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[?6h"
            + "\u{1B}[1dX"

        XCTAssertEqual(render(raw), "top\nXiddle\nbottom")
    }

    func testC0VerticalTabAndFormFeedBehaveLikeLineFeeds() {
        XCTAssertEqual(render("ab\u{0B}cd"), "ab\ncd")
        XCTAssertEqual(render("ab\u{0C}cd"), "ab\ncd")
    }

    func testStripsNonprintingC0AndDELControls() {
        XCTAssertEqual(render("a\u{00}b\u{0E}c\u{0F}d\u{18}e\u{1A}f\u{7F}g"), "abcdefg")
    }

    func testC0VerticalTabScrollsOnlyTheCurrentRegion() {
        let raw = [
            "header",
            "row1",
            "row2",
            "footer"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[3;1H"
            + "\u{0B}new"

        XCTAssertEqual(render(raw), "header\nrow2\nnew\nfooter")
    }

    func testIndexAndNextLineEscapesMoveCursorDown() {
        XCTAssertEqual(render("ab\u{1B}Dcd"), "ab\n  cd")
        XCTAssertEqual(render("ab\u{1B}Ecd"), "ab\ncd")
    }

    func testC1IndexAndNextLineControlsMoveCursorDown() {
        XCTAssertEqual(render("ab\u{84}cd"), "ab\n  cd")
        XCTAssertEqual(render("ab\u{85}cd"), "ab\ncd")
    }

    func testIndexEscapeScrollsOnlyTheCurrentRegion() {
        let raw = [
            "header",
            "row1",
            "row2",
            "footer"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[3;1H"
            + "\u{1B}Dnew"

        XCTAssertEqual(render(raw), "header\nrow2\nnew\nfooter")
    }

    func testReverseIndexScrollsDownInsideRegion() {
        let raw = [
            "header",
            "row1",
            "row2",
            "footer"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[2;1H"
            + "\u{1B}Mnew"

        XCTAssertEqual(render(raw), "header\nnew\nrow1\nfooter")
    }

    func testC1ReverseIndexScrollsDownInsideRegion() {
        let raw = [
            "header",
            "row1",
            "row2",
            "footer"
        ].joined(separator: "\n")
            + "\u{1B}[2;3r"
            + "\u{1B}[2;1H"
            + "\u{8D}new"

        XCTAssertEqual(render(raw), "header\nnew\nrow1\nfooter")
    }

    func testCSIExplicitScrollUpAndDownUseCurrentRegion() {
        let base = [
            "header",
            "row1",
            "row2",
            "footer"
        ].joined(separator: "\n")

        XCTAssertEqual(render(base + "\u{1B}[2;3r\u{1B}[S"), "header\nrow2\n\nfooter")
        XCTAssertEqual(render(base + "\u{1B}[2;3r\u{1B}[T"), "header\n\nrow1\nfooter")
    }

    func testInsertAndDeleteLineOperateInsideTheVisibleBuffer() {
        XCTAssertEqual(render("one\ntwo\nthree\u{1B}[2;1H\u{1B}[Lnew"), "one\nnew\ntwo")
        XCTAssertEqual(render("one\ntwo\nthree\u{1B}[2;1H\u{1B}[M"), "one\nthree\n")
    }

    func testInsertAndDeleteCharactersOperateAtCursor() {
        XCTAssertEqual(render("abcd\u{1B}[1;3H\u{1B}[@X"), "abXcd")
        XCTAssertEqual(render("abcdef\u{1B}[1;3H\u{1B}[2P"), "abef  ")
    }

    func testEraseCharactersBlanksCellsWithoutShiftingSuffix() {
        XCTAssertEqual(render("abcdef\u{1B}[1;3H\u{1B}[2X"), "ab  ef")
        XCTAssertEqual(render("abcdef\u{1B}[1;3H\u{1B}[X"), "ab def")
    }

    func testRepeatPreviousCharacterAppendsAtCursor() {
        XCTAssertEqual(render("ab\u{1B}[3b"), "abbbb")
        XCTAssertEqual(render("\u{1B}[3bX"), "X")
    }

    func testInsertAndDeleteCharactersRespectWideCellBoundaries() {
        XCTAssertEqual(render("界XYZ\u{1B}[1;2H\u{1B}[PX"), " XYZ ")
        XCTAssertEqual(render("界XYZ\u{1B}[1;2H\u{1B}[@A"), " A XYZ")
    }

    func testEraseCharactersRespectWideCellBoundaries() {
        XCTAssertEqual(render("A界Z\u{1B}[1;2H\u{1B}[X"), "A  Z")
        XCTAssertEqual(render("A界Z\u{1B}[1;3H\u{1B}[X"), "A  Z")
    }

    func testRepeatPreviousCharacterUsesWideGlyphStart() {
        XCTAssertEqual(render("界\u{1B}[2b"), "界界界")
        XCTAssertEqual(render("A界Z\u{1B}[1;4H\u{1B}[2b"), "A界界界")
    }

    func testAlternateScreenExitPreservesLatestFrameForTranscriptScrollback() {
        let raw = "before\n"
            + "\u{1B}[?1049h"
            + "ALT\nFRAME"
            + "\u{1B}[?1049l"
            + " after"

        XCTAssertEqual(render(raw), "before\nALT\nFRAME after")
    }

    func testStripsBellAndOSCTitleSequences() {
        XCTAssertEqual(render("ding\u{07}dong"), "dingdong")
        // OSC set-title terminated by BEL.
        XCTAssertEqual(render("\u{1B}]0;my title\u{07}prompt$ "), "prompt$ ")
        XCTAssertEqual(render("\u{1B}]0;my title\u{1B}\\prompt$ "), "prompt$ ")
        XCTAssertEqual(render("\u{9D}0;my title\u{07}prompt$ "), "prompt$ ")
        XCTAssertEqual(render("\u{9D}0;my title\u{9C}prompt$ "), "prompt$ ")
    }

    func testStripsTerminalStringControlPayloads() {
        XCTAssertEqual(render("a\u{1B}Pignored\u{1B}\\b"), "ab")
        XCTAssertEqual(render("a\u{1B}Xignored\u{1B}\\b"), "ab")
        XCTAssertEqual(render("a\u{1B}^ignored\u{1B}\\b"), "ab")
        XCTAssertEqual(render("a\u{1B}_ignored\u{1B}\\b"), "ab")
        XCTAssertEqual(render("a\u{90}ignored\u{9C}b"), "ab")
        XCTAssertEqual(render("a\u{98}ignored\u{9C}b"), "ab")
        XCTAssertEqual(render("a\u{9E}ignored\u{9C}b"), "ab")
        XCTAssertEqual(render("a\u{9F}ignored\u{9C}b"), "ab")
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

    func testWideCharactersAdvanceByTwoTerminalCells() {
        XCTAssertEqual(render("界X\u{1B}[1;3HY"), "界Y")
        XCTAssertEqual(render("\u{1F680}X\u{1B}[1;3HY"), "\u{1F680}Y")
    }

    func testWideCharacterOverwriteClearsContinuationCell() {
        XCTAssertEqual(render("界X\rA"), "A X")
        XCTAssertEqual(render("\u{1F680}X\rA"), "A X")
    }

    func testCombiningMarksDoNotAdvanceCursor() {
        XCTAssertEqual(render("e\u{0301}X\u{1B}[1;2HY"), "e\u{0301}Y")
    }

    func testZeroWidthJoinerEmojiClustersAdvanceAsOneWideGlyph() {
        XCTAssertEqual(render("👨‍👩‍👧‍👦X\u{1B}[1;3HY"), "👨‍👩‍👧‍👦Y")
        XCTAssertEqual(render("👩🏽‍💻X\u{1B}[1;3HY"), "👩🏽‍💻Y")
    }

    func testEmojiPresentationSequencesAdvanceAsWideGlyphs() {
        XCTAssertEqual(render("♥️X\u{1B}[1;3HY"), "♥️Y")
        XCTAssertEqual(render("☀️X\u{1B}[1;3HY"), "☀️Y")
        XCTAssertEqual(render("©️X\u{1B}[1;3HY"), "©️Y")
        XCTAssertEqual(render("™️X\u{1B}[1;3HY"), "™️Y")
        XCTAssertEqual(render("1️⃣X\u{1B}[1;3HY"), "1️⃣Y")
    }

    func testAmbiguousWidthPolicyDefaultsToNarrowForTranscriptStability() {
        XCTAssertEqual(render("ΩX\u{1B}[1;2HY"), "ΩY")
        XCTAssertEqual(TerminalScreenCellWidth.width(of: "Ω"), 1)
        XCTAssertEqual(TerminalScreenCellWidth.width(of: "Ω", ambiguousPolicy: .wide), 2)
    }

    func testAmbiguousWidthPolicyCanRenderWideForLocaleSpecificTerminalFrames() {
        let raw = "ΩX\u{1B}[1;3HY"

        XCTAssertEqual(render(raw), "ΩXY")
        XCTAssertEqual(render(raw, ambiguousWidthPolicy: .wide), "ΩY")
    }

    func testAmbiguousWidthPolicyAutomaticDefaultsToNarrowForNonCJKLocales() {
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "en_US", environment: [:]), .narrow)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "fr_FR.UTF-8", environment: [:]), .narrow)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "C", environment: [:]), .narrow)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: nil, environment: [:]), .narrow)
    }

    func testAmbiguousWidthPolicyAutomaticUsesWideForCJKLocales() {
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "ja_JP", environment: [:]), .wide)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "ko-KR.UTF-8", environment: [:]), .wide)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "zh-Hant-TW", environment: [:]), .wide)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "yue_HK", environment: [:]), .wide)
    }

    func testAmbiguousWidthPolicyAutomaticUsesProcessLocaleEnvironment() {
        XCTAssertEqual(
            TerminalOutputAmbiguousWidthPolicy.automatic(
                localeIdentifier: "en_US",
                environment: ["LANG": "zh_CN.UTF-8"]
            ),
            .wide
        )
        XCTAssertEqual(
            TerminalOutputAmbiguousWidthPolicy.automatic(
                localeIdentifier: "en_US",
                environment: ["LC_CTYPE": "ja_JP.UTF-8", "LANG": "en_US.UTF-8"]
            ),
            .wide
        )
        XCTAssertEqual(
            TerminalOutputAmbiguousWidthPolicy.automatic(
                localeIdentifier: nil,
                environment: ["LC_ALL": "ko_KR.UTF-8"]
            ),
            .wide
        )
        XCTAssertEqual(
            TerminalOutputAmbiguousWidthPolicy.automatic(
                localeIdentifier: "ja_JP",
                environment: ["LC_ALL": "C"]
            ),
            .narrow
        )
    }

    func testAmbiguousWidthPolicyAutomaticEnvironmentOverrideWins() {
        let key = TerminalOutputAmbiguousWidthPolicy.environmentOverrideName

        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "ja_JP", environment: [key: "narrow"]), .narrow)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "en_US", environment: [key: "wide"]), .wide)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "en_US", environment: [key: " cjk "]), .wide)
        XCTAssertEqual(TerminalOutputAmbiguousWidthPolicy.automatic(localeIdentifier: "ja_JP", environment: [key: "invalid"]), .wide)
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
        // A hostile/garbled huge move must not pad millions of rows.
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
