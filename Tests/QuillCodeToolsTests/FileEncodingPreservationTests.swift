import XCTest
import Foundation
@testable import QuillCodeTools

// MARK: - Unit: the pure detect/apply/normalize helper

final class FileEncodingPreservationTests: XCTestCase {
    private let bom = Data([0xEF, 0xBB, 0xBF])

    // detect

    func testDetectPlainLF() {
        let style = FileEncodingPreservation.detect(Data("a\nb\n".utf8))
        XCTAssertFalse(style.hasBOM)
        XCTAssertEqual(style.lineEnding, .lf)
    }

    func testDetectCRLF() {
        let style = FileEncodingPreservation.detect(Data("a\r\nb\r\n".utf8))
        XCTAssertFalse(style.hasBOM)
        XCTAssertEqual(style.lineEnding, .crlf)
    }

    func testDetectBOMWithCRLF() {
        let style = FileEncodingPreservation.detect(bom + Data("a\r\nb\r\n".utf8))
        XCTAssertTrue(style.hasBOM)
        XCTAssertEqual(style.lineEnding, .crlf)
    }

    func testDetectBOMWithLF() {
        let style = FileEncodingPreservation.detect(bom + Data("a\nb\n".utf8))
        XCTAssertTrue(style.hasBOM)
        XCTAssertEqual(style.lineEnding, .lf)
    }

    func testDetectEmptyDefaultsToLFNoBOM() {
        XCTAssertEqual(FileEncodingPreservation.detect(Data()), .default)
    }

    func testDetectSingleLineNoNewlineDefaultsToLF() {
        XCTAssertEqual(FileEncodingPreservation.detect(Data("no newline here".utf8)).lineEnding, .lf)
    }

    func testDetectMajorityWins() {
        // Two CRLF, one LF → CRLF.
        XCTAssertEqual(FileEncodingPreservation.detect(Data("a\r\nb\r\nc\nd".utf8)).lineEnding, .crlf)
        // Two LF, one CRLF → LF.
        XCTAssertEqual(FileEncodingPreservation.detect(Data("a\nb\nc\r\nd".utf8)).lineEnding, .lf)
    }

    // apply

    func testApplyLFStyleLeavesContent() {
        let data = FileEncodingPreservation.apply("a\nb\n", style: .default)
        XCTAssertEqual(data, Data("a\nb\n".utf8))
    }

    func testApplyCRLFStyleRelines() {
        let data = FileEncodingPreservation.apply("a\nb\n", style: .init(hasBOM: false, lineEnding: .crlf))
        XCTAssertEqual(data, Data("a\r\nb\r\n".utf8))
    }

    func testApplyBOMStylePrepends() {
        let data = FileEncodingPreservation.apply("a\n", style: .init(hasBOM: true, lineEnding: .lf))
        XCTAssertEqual(data, bom + Data("a\n".utf8))
    }

    func testApplyCanonicalizesIncomingCRLFNoDoubling() {
        // Incoming content that already has CRLF must not become CR-CR-LF under a CRLF style.
        let data = FileEncodingPreservation.apply("a\r\nb\r\n", style: .init(hasBOM: false, lineEnding: .crlf))
        XCTAssertEqual(data, Data("a\r\nb\r\n".utf8))
    }

    func testRoundTripPreserves() {
        let original = bom + Data("x\r\ny\r\nz".utf8)
        let style = FileEncodingPreservation.detect(original)
        // The model reads it as LF (display-normalized) and writes that back.
        let rewritten = FileEncodingPreservation.apply("x\ny\nz", style: style)
        XCTAssertEqual(rewritten, original)
    }

    // normalizeForDisplay

    func testNormalizeStripsBOMAndCRLF() {
        XCTAssertEqual(FileEncodingPreservation.normalizeForDisplay("\u{FEFF}a\r\nb\r\n"), "a\nb\n")
    }

    func testNormalizeLeavesPlainText() {
        XCTAssertEqual(FileEncodingPreservation.normalizeForDisplay("a\nb\n"), "a\nb\n")
    }
}
