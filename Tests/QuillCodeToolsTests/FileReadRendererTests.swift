import XCTest
import Foundation
@testable import QuillCodeTools

final class FileReadRendererTests: XCTestCase {
    func testNumbersLinesFromOne() {
        XCTAssertEqual(FileReadRenderer.render("a\nb\nc"), "1\ta\n2\tb\n3\tc")
    }

    func testTrailingNewlineIsNotACountedLine() {
        // "a\nb\n" is two lines, not three.
        XCTAssertEqual(FileReadRenderer.render("a\nb\n"), "1\ta\n2\tb")
    }

    func testEmptyFile() {
        XCTAssertEqual(FileReadRenderer.render(""), "[empty file]")
    }

    func testPaginationWindowAndFooter() {
        let text = (1...10).map { "line\($0)" }.joined(separator: "\n")
        let out = FileReadRenderer.render(text, offset: 3, limit: 2)
        XCTAssertTrue(out.contains("3\tline3"))
        XCTAssertTrue(out.contains("4\tline4"))
        XCTAssertFalse(out.contains("\tline5"))
        XCTAssertTrue(out.contains("showing lines 3–4 of 10"), out)
        XCTAssertTrue(out.contains("offset=5"), out)
    }

    func testRightAlignsLineNumbers() {
        let text = (1...10).map { _ in "x" }.joined(separator: "\n")
        let out = FileReadRenderer.render(text)
        // Two-digit total -> single-digit numbers are space-padded to width 2.
        XCTAssertTrue(out.hasPrefix(" 1\tx"), out)
        XCTAssertTrue(out.contains("\n10\tx"), out)
    }

    func testPerLineTruncation() {
        let long = String(repeating: "z", count: 5000)
        let out = FileReadRenderer.render(long, maxLineLength: 100)
        XCTAssertTrue(out.contains("[line truncated]"), out)
        XCTAssertLessThan(out.count, 5000)
    }

    func testOffsetPastEnd() {
        XCTAssertTrue(FileReadRenderer.render("a\nb", offset: 99).contains("past the end"))
    }

    func testBinaryDetection() {
        XCTAssertTrue(FileReadRenderer.isProbablyBinary(Data([0x00, 0x01, 0x02])))
        XCTAssertFalse(FileReadRenderer.isProbablyBinary(Data("plain text".utf8)))
    }

    func testBinaryDescriptionNamesImageKind() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let desc = FileReadRenderer.binaryDescription(png, fileName: "logo.png")
        XCTAssertTrue(desc.contains("PNG image"), desc)
        XCTAssertTrue(desc.contains("logo.png"), desc)
    }
}
