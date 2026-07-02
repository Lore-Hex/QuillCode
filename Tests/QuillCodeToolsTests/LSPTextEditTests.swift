import Foundation
import XCTest
@testable import QuillCodeTools

final class LSPTextEditTests: XCTestCase {
    private func edit(_ sl: Int, _ sc: Int, _ el: Int, _ ec: Int, _ text: String) -> LSPTextEdit {
        LSPTextEdit(
            range: LSPRange(start: LSPPosition(line: sl, character: sc), end: LSPPosition(line: el, character: ec)),
            newText: text
        )
    }

    func testEmptyEditsAreIdentity() {
        let text = "let x = 1\n"
        XCTAssertEqual(LSPEditApplier.apply([], to: text), text)
    }

    func testWholeDocumentReplacement() {
        let original = "let  x=1\n"
        // sourcekit-lsp commonly returns a single full-range edit with the formatted document.
        let formatted = "let x = 1\n"
        let result = LSPEditApplier.apply([edit(0, 0, 1, 0, formatted)], to: original)
        XCTAssertEqual(result, formatted)
    }

    func testMultipleNonOverlappingEditsApplyEndToStart() {
        let original = "a\nb\nc\n"
        // Replace line 0 "a" -> "A" and line 2 "c" -> "C"; order in the array is start-to-end.
        let edits = [
            edit(0, 0, 0, 1, "A"),
            edit(2, 0, 2, 1, "C")
        ]
        XCTAssertEqual(LSPEditApplier.apply(edits, to: original), "A\nb\nC\n")
    }

    func testIdempotenceReapplyingFormattedTextYieldsSame() {
        let formatted = "let x = 1\n"
        // A formatter that returns the same text as a full-range edit must not change anything.
        let result = LSPEditApplier.apply([edit(0, 0, 1, 0, formatted)], to: formatted)
        XCTAssertEqual(result, formatted)
    }

    func testEditPastEndOfDocumentIsRejected() {
        let original = "short\n"
        // A start line far past the document is malformed — apply must refuse (return nil) so the
        // caller keeps the original file.
        let result = LSPEditApplier.apply([edit(99, 0, 99, 1, "x")], to: original)
        XCTAssertNil(result)
    }

    func testEditWithEndBeforeStartIsRejected() {
        let original = "abcdef\n"
        let result = LSPEditApplier.apply([edit(0, 4, 0, 2, "x")], to: original)
        XCTAssertNil(result)
    }

    func testUnicodeOffsetsUseUTF16CodeUnits() {
        // "é" is one UTF-16 unit; an emoji is two. Editing after them must land correctly.
        let original = "é😀X\n"
        // Replace the "X" — it is at UTF-16 offset 3 (é=1, 😀=2).
        let result = LSPEditApplier.apply([edit(0, 3, 0, 4, "Y")], to: original)
        XCTAssertEqual(result, "é😀Y\n")
    }

    func testInsertionAtEndOfFile() {
        let original = "line\n"
        // Insert at the position just past the final newline (line 1, char 0).
        let result = LSPEditApplier.apply([edit(1, 0, 1, 0, "added\n")], to: original)
        XCTAssertEqual(result, "line\nadded\n")
    }

    func testOverlappingEditsAreRejectedNotCrashed() {
        // An untrusted server violating the no-overlap guarantee must NOT crash the applier. Two edits
        // whose ranges overlap (both valid against the original length) must return nil (keep original).
        let original = "0123456789\n"
        let edits = [
            edit(0, 0, 0, 9, ""),   // delete [0,9)
            edit(0, 3, 0, 10, "Z")  // overlaps the first edit's range
        ]
        XCTAssertNil(LSPEditApplier.apply(edits, to: original), "overlapping edits must be rejected, not crash")
    }

    func testAdjacentNonOverlappingEditsAreAccepted() {
        // Edits that touch at a boundary ([0,3) and [3,6)) do NOT overlap and must apply.
        let original = "aaabbb\n"
        let edits = [
            edit(0, 0, 0, 3, "X"),
            edit(0, 3, 0, 6, "Y")
        ]
        XCTAssertEqual(LSPEditApplier.apply(edits, to: original), "XY\n")
    }
}
