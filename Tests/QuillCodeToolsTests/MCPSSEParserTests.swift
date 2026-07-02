import Foundation
import XCTest
@testable import QuillCodeTools

final class MCPSSEParserTests: XCTestCase {
    func testParsesSingleEvent() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("event: message\ndata: {\"a\":1}\n\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "message")
        XCTAssertEqual(events[0].data, "{\"a\":1}")
    }

    func testDefaultsEventNameToMessage() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("data: hello\n\n".utf8))
        XCTAssertEqual(events.first?.event, "message")
        XCTAssertEqual(events.first?.data, "hello")
    }

    func testJoinsMultipleDataLines() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("data: line1\ndata: line2\n\n".utf8))
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func testReassemblesPartialFramesAcrossChunks() throws {
        var parser = MCPSSEParser()
        XCTAssertTrue(try parser.append(Data("data: par".utf8)).isEmpty)
        XCTAssertTrue(try parser.append(Data("tial".utf8)).isEmpty)
        let events = try parser.append(Data("\n\n".utf8))
        XCTAssertEqual(events.first?.data, "partial")
    }

    func testHandlesCRLFTerminators() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("data: crlf\r\n\r\n".utf8))
        XCTAssertEqual(events.first?.data, "crlf")
    }

    // Regression: a spec-compliant server that puts CRLF BETWEEN fields (not just at the frame
    // terminator). Character-level splitting drops these because "\r\n" is one grapheme cluster.
    func testParsesCRLFBetweenFields() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("event: message\r\ndata: {\"a\":1}\r\n\r\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "message")
        XCTAssertEqual(events[0].data, "{\"a\":1}")
    }

    func testParsesLoneCRBetweenFields() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("event: message\rdata: payload\r\r".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "message")
        XCTAssertEqual(events[0].data, "payload")
    }

    func testJoinsMultipleCRLFDataLines() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("data: line1\r\ndata: line2\r\n\r\n".utf8))
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func testSplitLinesHandlesMixedNewlines() {
        // Direct check of the scalar-level splitter across LF, CRLF, and lone CR.
        XCTAssertEqual(MCPSSEParser.splitLines("a\r\nb\nc\rd"), ["a", "b", "c", "d"])
    }

    func testIgnoresCommentsAndKeepAlives() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data(": keep-alive\n\ndata: real\n\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "real")
    }

    func testCapturesEventID() throws {
        var parser = MCPSSEParser()
        let events = try parser.append(Data("id: 42\ndata: x\n\n".utf8))
        XCTAssertEqual(events.first?.id, "42")
    }

    func testRejectsOversizedUnterminatedFrame() {
        var parser = MCPSSEParser(maxEventBytes: 1024)
        let huge = Data(repeating: 0x61, count: 4096)
        XCTAssertThrowsError(try parser.append(Data("data: ".utf8) + huge))
    }

    func testLossilyDecodesInvalidUTF8() throws {
        var parser = MCPSSEParser()
        var bytes = Data("data: ".utf8)
        bytes.append(0xFF) // invalid UTF-8 byte
        bytes.append(contentsOf: Data("\n\n".utf8))
        let events = try parser.append(bytes)
        XCTAssertEqual(events.count, 1) // did not crash; produced an event
    }
}
