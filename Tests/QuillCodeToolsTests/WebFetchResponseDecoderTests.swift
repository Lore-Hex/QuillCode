import XCTest
@testable import QuillCodeTools

final class WebFetchResponseDecoderTests: XCTestCase {
    // MARK: - Classification

    func testHTMLTypesClassifyAsHTML() {
        XCTAssertEqual(WebFetchResponseDecoder.classify(contentType: "text/html", bodyPrefix: Data()), .html)
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "TEXT/HTML; charset=UTF-8", bodyPrefix: Data()),
            .html
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "application/xhtml+xml", bodyPrefix: Data()),
            .html
        )
    }

    func testTextTypesPassThrough() {
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "text/markdown", bodyPrefix: Data()),
            .passthroughText
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "text/plain; charset=us-ascii", bodyPrefix: Data()),
            .passthroughText
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "text/csv", bodyPrefix: Data()),
            .otherText
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "application/json", bodyPrefix: Data()),
            .otherText
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "application/problem+json", bodyPrefix: Data()),
            .otherText
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "application/rss+xml", bodyPrefix: Data()),
            .otherText
        )
    }

    func testBinaryTypesAreRefused() {
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "application/pdf", bodyPrefix: Data()),
            .refused(reportedType: "application/pdf")
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "application/octet-stream", bodyPrefix: Data()),
            .refused(reportedType: "application/octet-stream")
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: "image/jpeg", bodyPrefix: Data()),
            .refused(reportedType: "image/jpeg")
        )
    }

    func testMissingContentTypeSniffs() {
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: nil, bodyPrefix: Data("<!doctype HTML><html>".utf8)),
            .html
        )
        XCTAssertEqual(
            WebFetchResponseDecoder.classify(contentType: nil, bodyPrefix: Data("plain words".utf8)),
            .passthroughText
        )
        if case .refused = WebFetchResponseDecoder.classify(contentType: nil, bodyPrefix: Data([0x00, 0x01])) {
            // NUL bytes with no declared type read as binary.
        } else {
            XCTFail("NUL-laden body without a content type must be refused")
        }
    }

    func testEmptyContentTypeDoesNotCrash() {
        _ = WebFetchResponseDecoder.classify(contentType: "", bodyPrefix: Data())
        _ = WebFetchResponseDecoder.classify(contentType: ";;;", bodyPrefix: Data())
        XCTAssertEqual(WebFetchResponseDecoder.mimeType(of: ""), "")
        XCTAssertEqual(WebFetchResponseDecoder.mimeType(of: ";charset=utf-8"), "")
    }

    // MARK: - Charset parameter parsing

    func testCharsetParameterExtraction() {
        XCTAssertEqual(WebFetchResponseDecoder.charset(of: "text/html; charset=utf-8"), "utf-8")
        XCTAssertEqual(WebFetchResponseDecoder.charset(of: "text/html;charset=\"ISO-8859-1\""), "iso-8859-1")
        XCTAssertEqual(WebFetchResponseDecoder.charset(of: "text/html; boundary=x; charset='windows-1252'"), "windows-1252")
        XCTAssertNil(WebFetchResponseDecoder.charset(of: "text/html"))
        XCTAssertNil(WebFetchResponseDecoder.charset(of: "text/html; charset="))
        XCTAssertNil(WebFetchResponseDecoder.charset(of: nil))
    }

    // MARK: - Decoding

    func testUTF8BOMIsStripped() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Data("hello".utf8))
        XCTAssertEqual(WebFetchResponseDecoder.decode(data, declaredCharset: "utf-8", sniffHTMLMeta: false), "hello")
    }

    func testUTF16BOMDecodes() {
        let data = "hi there".data(using: .utf16)! // includes BOM
        XCTAssertEqual(WebFetchResponseDecoder.decode(data, declaredCharset: nil, sniffHTMLMeta: false), "hi there")
    }

    func testUnknownCharsetFallsBackToLossyUTF8() {
        var data = Data("ok ".utf8)
        data.append(0xFF)
        let text = WebFetchResponseDecoder.decode(data, declaredCharset: "x-mystery-encoding", sniffHTMLMeta: false)
        XCTAssertTrue(text.hasPrefix("ok "))
        XCTAssertTrue(text.unicodeScalars.contains { $0.value == 0xFFFD })
    }

    func testNULBytesAreStripped() {
        let data = Data("a\u{0}b".utf8)
        XCTAssertEqual(WebFetchResponseDecoder.decode(data, declaredCharset: "utf-8", sniffHTMLMeta: false), "ab")
    }

    func testMetaCharsetSniffVariants() {
        let single = Data("<meta charset='shift_jis'>".utf8)
        let decodedSingle = WebFetchResponseDecoder.decode(
            Data("<meta charset='utf-8'><p>plain</p>".utf8),
            declaredCharset: nil,
            sniffHTMLMeta: true
        )
        XCTAssertTrue(decodedSingle.contains("plain"))
        _ = WebFetchResponseDecoder.decode(single, declaredCharset: nil, sniffHTMLMeta: true)

        let httpEquiv = Data(
            "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-1\"><p>\u{E9}</p>"
                .data(using: .isoLatin1)!
        )
        let decoded = WebFetchResponseDecoder.decode(httpEquiv, declaredCharset: nil, sniffHTMLMeta: true)
        XCTAssertTrue(decoded.contains("é"), "http-equiv charset must be honored: \(decoded)")
    }
}
