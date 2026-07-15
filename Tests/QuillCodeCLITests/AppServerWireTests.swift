import Foundation
@testable import QuillCodeCLI
import XCTest

final class AppServerWireTests: XCTestCase {
    func testInboundWirePreservesIntegerAndStringRequestIDs() throws {
        let integer = try AppServerInboundMessage(data: Data(#"{"id":42,"method":"thread/list","params":{}}"#.utf8))
        let string = try AppServerInboundMessage(data: Data(#"{"id":"request-1","method":"thread/read","params":{"threadId":"x"}}"#.utf8))

        XCTAssertEqual(integer, .request(id: .integer(42), method: "thread/list", params: .object([:])))
        XCTAssertEqual(
            string,
            .request(
                id: .string("request-1"),
                method: "thread/read",
                params: .object(["threadId": .string("x")])
            )
        )
    }

    func testOutboundWireMatchesCodexJSONLShapeWithoutJSONRPCMarker() throws {
        let line = try AppServerWireCodec.line(.response(
            id: .integer(7),
            result: .object(["ok": .bool(true)])
        ))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["id"] as? Int, 7)
        XCTAssertEqual((object["result"] as? [String: Any])?["ok"] as? Bool, true)
        XCTAssertNil(object["jsonrpc"])
        XCTAssertTrue(line.hasSuffix("\n"))
    }

    func testLineFramerHandlesChunkBoundariesCRLFAndFinalLine() throws {
        var framer = CLIInputLineFramer(maxLineBytes: 32)
        XCTAssertEqual(try framer.append(Data("one\r".utf8)), [])
        XCTAssertEqual(try framer.append(Data("\ntwo\npar".utf8)), [Data("one".utf8), Data("two".utf8)])
        XCTAssertEqual(try framer.append(Data("tial".utf8)), [])
        XCTAssertEqual(try framer.finish(), Data("partial".utf8))
        XCTAssertNil(try framer.finish())
    }

    func testLineFramerRejectsOversizedPartialAndCompletedLines() {
        var partial = CLIInputLineFramer(maxLineBytes: 3)
        XCTAssertThrowsError(try partial.append(Data("four".utf8))) { error in
            XCTAssertEqual(error as? CLIError, .appServerMessageTooLarge(limit: 3))
        }

        var completed = CLIInputLineFramer(maxLineBytes: 3)
        XCTAssertThrowsError(try completed.append(Data("four\n".utf8))) { error in
            XCTAssertEqual(error as? CLIError, .appServerMessageTooLarge(limit: 3))
        }
    }

    func testLineFramerHandlesManySmallMessagesInOneChunk() throws {
        let expected = (0..<10_000).map { "{\"id\":\($0)}" }
        var framer = CLIInputLineFramer(maxLineBytes: 64)

        let lines = try framer.append(Data((expected.joined(separator: "\n") + "\n").utf8))

        XCTAssertEqual(lines.count, expected.count)
        XCTAssertEqual(lines.first, Data(expected[0].utf8))
        XCTAssertEqual(lines.last, Data(expected[expected.count - 1].utf8))
        XCTAssertNil(try framer.finish())
    }
}
