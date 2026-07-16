import XCTest
@testable import QuillCodeApp

final class MessageMarkdownBlocksTests: XCTestCase {
    func testPlainProseIsOneParagraph() {
        XCTAssertEqual(
            MessageMarkdownBlocks.parse("Hello there.\nSecond line."),
            [.paragraph("Hello there.\nSecond line.")]
        )
    }

    func testFencedCodeBlockSplitsProse() {
        // The real daily-drive answer shape: prose, a ```python fence, more prose.
        let text = """
        **Fix in `main.py`:**
        ```python
        def add(a, b):
            return a + b
        ```
        All tests pass.
        """
        XCTAssertEqual(MessageMarkdownBlocks.parse(text), [
            .paragraph("**Fix in `main.py`:**"),
            .code(language: "python", content: "def add(a, b):\n    return a + b"),
            .paragraph("All tests pass.")
        ])
    }

    func testUnclosedFenceRendersAsCodeToTheEnd() {
        // A streaming reply's half-arrived code block must render as code, not a stray ``` line.
        let text = "Look:\n```swift\nlet x = 1"
        XCTAssertEqual(MessageMarkdownBlocks.parse(text), [
            .paragraph("Look:"),
            .code(language: "swift", content: "let x = 1")
        ])
    }

    func testBareFenceHasNoLanguage() {
        XCTAssertEqual(MessageMarkdownBlocks.parse("```\nplain\n```"), [
            .code(language: nil, content: "plain")
        ])
    }

    func testInlineAttributedRendersBoldAndCode() throws {
        let attributed = try XCTUnwrap(
            MessageMarkdownBlocks.inlineAttributed("**Bug:** the `add(a, b)` function")
        )
        let rendered = String(attributed.characters)
        // The markdown SYNTAX is consumed — no literal asterisks or backticks survive.
        XCTAssertFalse(rendered.contains("**"))
        XCTAssertFalse(rendered.contains("`"))
        XCTAssertTrue(rendered.contains("Bug:"))
        XCTAssertTrue(rendered.contains("add(a, b)"))
    }

    func testInlineAttributedPreservesLineBreaks() throws {
        let attributed = try XCTUnwrap(
            MessageMarkdownBlocks.inlineAttributed("**What happened:**\n1. Ran the suite.\n2. Fixed it.")
        )
        XCTAssertEqual(String(attributed.characters).components(separatedBy: "\n").count, 3)
    }

    func testReplacementCharactersAreStrippedForDisplay() {
        // Server-corrupted "test_add ���" renders clean; the raw record keeps the original.
        XCTAssertEqual(
            MessageMarkdownBlocks.strippingReplacementCharacters("- `test_add` \u{FFFD}\u{FFFD}\u{FFFD}\n- `test_greet` ✓"),
            "- `test_add`\n- `test_greet` ✓"
        )
        XCTAssertEqual(
            MessageMarkdownBlocks.strippingReplacementCharacters("mid \u{FFFD} sentence"),
            "mid sentence"
        )
        let untouched = "no corruption here ✓ ✅"
        XCTAssertEqual(MessageMarkdownBlocks.strippingReplacementCharacters(untouched), untouched)
    }

    func testProseWithoutMarkdownUsesPlainFastPath() {
        XCTAssertNil(MessageMarkdownBlocks.inlineAttributed("Nothing fancy here."))
    }

    func testAtxHeadingsBecomeHeadingBlocks() {
        XCTAssertEqual(MessageMarkdownBlocks.parse("# Title\n## Sub\n### Small"), [
            .heading(level: 1, text: "Title"),
            .heading(level: 2, text: "Sub"),
            .heading(level: 3, text: "Small")
        ])
    }

    func testHeadingRequiresSpaceAndLevelOneToThree() {
        // No space after the hashes, a bare '#', and levels 4+ all stay prose — never a heading.
        XCTAssertEqual(MessageMarkdownBlocks.parse("#nospace"), [.paragraph("#nospace")])
        XCTAssertEqual(MessageMarkdownBlocks.parse("#### Deep"), [.paragraph("#### Deep")])
        XCTAssertEqual(MessageMarkdownBlocks.parse("#"), [.paragraph("#")])
    }

    func testUnorderedListAccumulatesAcrossDashAndStar() {
        XCTAssertEqual(MessageMarkdownBlocks.parse("- one\n- two\n* three"), [
            .list(ordered: false, items: ["one", "two", "three"])
        ])
    }

    func testOrderedListAccumulates() {
        XCTAssertEqual(MessageMarkdownBlocks.parse("1. first\n2. second"), [
            .list(ordered: true, items: ["first", "second"])
        ])
    }

    func testListSeparatesFromSurroundingProse() {
        let text = "Steps:\n- a\n- b\nDone."
        XCTAssertEqual(MessageMarkdownBlocks.parse(text), [
            .paragraph("Steps:"),
            .list(ordered: false, items: ["a", "b"]),
            .paragraph("Done.")
        ])
    }

    func testInlineEmphasisIsNotMistakenForABullet() {
        // '*italic*' / '**bold**' have no space after the marker, so they stay prose, not a list.
        XCTAssertEqual(
            MessageMarkdownBlocks.parse("*italic* and **bold** text"),
            [.paragraph("*italic* and **bold** text")]
        )
    }

    func testSwitchingListMarkerStartsANewList() {
        // An ordered item after unordered ones flushes the first list rather than merging.
        XCTAssertEqual(MessageMarkdownBlocks.parse("- a\n1. b"), [
            .list(ordered: false, items: ["a"]),
            .list(ordered: true, items: ["b"])
        ])
    }

    func testListItemsPreserveInlineMarkdownForTheRenderer() {
        // The parser hands the renderer raw item text so inline bold/`code` still styles per-item.
        XCTAssertEqual(
            MessageMarkdownBlocks.parse("- fix `add(a, b)`\n- run **tests**"),
            [.list(ordered: false, items: ["fix `add(a, b)`", "run **tests**"])]
        )
    }
}
