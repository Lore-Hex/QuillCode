import Foundation
import XCTest
@testable import QuillCodeTools

final class LSPMessageCodecTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": 7, "method": "textDocument/definition"]
        let encoded = try LSPMessageCodec.encode(object)
        let header = String(decoding: encoded.prefix(40), as: UTF8.self)
        XCTAssertTrue(header.hasPrefix("Content-Length: "))

        var buffer = encoded
        let message = try XCTUnwrap(LSPMessageCodec.nextMessage(from: &buffer))
        XCTAssertTrue(buffer.isEmpty, "the full frame should have been consumed")
        let decoded = try LSPMessageCodec.decode(message)
        XCTAssertEqual(decoded["id"] as? Int, 7)
        XCTAssertEqual(decoded["method"] as? String, "textDocument/definition")
    }

    func testTwoMessagesInOneBuffer() throws {
        var buffer = Data()
        buffer.append(try LSPMessageCodec.encode(["id": 1]))
        buffer.append(try LSPMessageCodec.encode(["id": 2]))

        let first = try LSPMessageCodec.decode(try XCTUnwrap(LSPMessageCodec.nextMessage(from: &buffer)))
        let second = try LSPMessageCodec.decode(try XCTUnwrap(LSPMessageCodec.nextMessage(from: &buffer)))
        XCTAssertEqual(first["id"] as? Int, 1)
        XCTAssertEqual(second["id"] as? Int, 2)
        XCTAssertNil(try LSPMessageCodec.nextMessage(from: &buffer))
    }

    func testPartialHeaderReturnsNilThenCompletes() throws {
        let full = try LSPMessageCodec.encode(["id": 42])
        // Split mid-header: only the first few bytes have arrived.
        var buffer = full.prefix(10)
        XCTAssertNil(try LSPMessageCodec.nextMessage(from: &buffer), "an incomplete header is not a message yet")
        buffer.append(full.suffix(from: full.index(full.startIndex, offsetBy: 10)))
        let message = try XCTUnwrap(LSPMessageCodec.nextMessage(from: &buffer))
        XCTAssertEqual(try LSPMessageCodec.decode(message)["id"] as? Int, 42)
    }

    func testPartialBodyReturnsNilThenCompletes() throws {
        let full = try LSPMessageCodec.encode(["method": "hello", "id": 3])
        // Everything except the last byte of the body.
        var buffer = full.prefix(full.count - 1)
        XCTAssertNil(try LSPMessageCodec.nextMessage(from: &buffer), "an incomplete body is not a message yet")
        buffer.append(full.suffix(1))
        let message = try XCTUnwrap(LSPMessageCodec.nextMessage(from: &buffer))
        XCTAssertEqual(try LSPMessageCodec.decode(message)["id"] as? Int, 3)
    }

    func testCaseInsensitiveHeaderAndExtraHeaders() throws {
        let body = Data(#"{"id":9}"#.utf8)
        var buffer = Data("content-length: \(body.count)\r\nContent-Type: application/vscode-jsonrpc\r\n\r\n".utf8)
        buffer.append(body)
        let message = try XCTUnwrap(LSPMessageCodec.nextMessage(from: &buffer))
        XCTAssertEqual(try LSPMessageCodec.decode(message)["id"] as? Int, 9)
    }

    func testMissingContentLengthThrows() {
        var buffer = Data("X-Whatever: 1\r\n\r\n{}".utf8)
        XCTAssertThrowsError(try LSPMessageCodec.nextMessage(from: &buffer)) { error in
            guard case LSPError.invalidMessage = error else { return XCTFail("expected invalidMessage") }
        }
    }

    func testNegativeContentLengthThrows() {
        var buffer = Data("Content-Length: -5\r\n\r\n".utf8)
        XCTAssertThrowsError(try LSPMessageCodec.nextMessage(from: &buffer)) { error in
            guard case LSPError.invalidMessage = error else { return XCTFail("expected invalidMessage") }
        }
    }

    func testOversizedBodyThrows() {
        var buffer = Data("Content-Length: \(LSPMessageCodec.maxMessageBytes + 1)\r\n\r\n".utf8)
        buffer.append(Data(repeating: 0x20, count: 16)) // some body bytes so the header is complete
        XCTAssertThrowsError(try LSPMessageCodec.nextMessage(from: &buffer)) { error in
            guard case LSPError.invalidMessage = error else { return XCTFail("expected invalidMessage") }
        }
    }

    func testNonObjectBodyIsRejected() {
        let arrayBody = Data("[1,2,3]".utf8)
        XCTAssertThrowsError(try LSPMessageCodec.decode(arrayBody)) { error in
            guard case LSPError.invalidMessage = error else { return XCTFail("expected invalidMessage") }
        }
    }

    func testGarbageBodyIsRejected() {
        XCTAssertThrowsError(try LSPMessageCodec.decode(Data("not json".utf8))) { error in
            guard case LSPError.invalidMessage = error else { return XCTFail("expected invalidMessage") }
        }
    }
}
