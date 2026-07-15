import Foundation
@testable import QuillCodeCLI
import XCTest

final class MCPServerWireTests: XCTestCase {
    func testDecodesStrictJSONRPCRequestsNotificationsAndResponses() throws {
        XCTAssertEqual(
            try MCPServerInboundMessage(data: Data(
                #"{"jsonrpc":"2.0","id":"a","method":"ping","params":{}}"#.utf8
            )),
            .request(id: .string("a"), method: "ping", params: .object([:]))
        )
        XCTAssertEqual(
            try MCPServerInboundMessage(data: Data(
                #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8
            )),
            .notification(method: "notifications/initialized", params: .object([:]))
        )
        XCTAssertEqual(
            try MCPServerInboundMessage(data: Data(
                #"{"jsonrpc":"2.0","id":7,"result":{"decision":"approved"}}"#.utf8
            )),
            .response(
                id: .integer(7),
                result: .object(["decision": .string("approved")]),
                error: nil
            )
        )
    }

    func testRejectsMissingOrWrongJSONRPCVersionAndInvalidEnvelope() {
        for text in [
            #"{"id":1,"method":"ping"}"#,
            #"{"jsonrpc":"1.0","id":1,"method":"ping"}"#,
            #"{"jsonrpc":"2.0","id":1}"#
        ] {
            XCTAssertThrowsError(try MCPServerInboundMessage(data: Data(text.utf8)))
        }
    }

    func testEveryOutboundShapeIncludesJSONRPCVersion() throws {
        let messages: [MCPServerOutboundMessage] = [
            .response(id: .integer(1), result: .object([:])),
            .error(id: nil, error: .parseError),
            .notification(method: "codex/event", params: .object([:])),
            .request(id: .string("approval"), method: "elicitation/create", params: .object([:]))
        ]
        for message in messages {
            let data = Data(try MCPServerWireCodec.line(message).utf8)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        }
    }
}
