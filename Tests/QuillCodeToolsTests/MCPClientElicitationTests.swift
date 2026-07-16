import Foundation
import XCTest
@testable import QuillCodeTools

final class MCPClientElicitationTests: XCTestCase {
    func testCapabilitiesAdvertiseStandardAndOpenAIFormIndependently() throws {
        let standard = MCPClientCapabilities(supportsFormElicitation: true).initializeObject
        XCTAssertNotNil(standard["elicitation"] as? [String: Any])
        XCTAssertNil(standard["extensions"])

        let rich = MCPClientCapabilities(
            supportsFormElicitation: true,
            supportsOpenAIFormElicitation: true
        ).initializeObject
        let extensions = try XCTUnwrap(rich["extensions"] as? [String: Any])
        XCTAssertNotNil(extensions["openai/form"] as? [String: Any])
    }

    func testDecodesTypedFormAndRemovesProgressMetadata() throws {
        let envelope = try MCPServerElicitationEnvelope.decode(from: [
            "jsonrpc": "2.0",
            "id": "request-1",
            "method": "elicitation/create",
            "params": [
                "mode": "form",
                "message": "Confirm the calendar action",
                "requestedSchema": [
                    "type": "object",
                    "properties": [
                        "confirmed": ["type": "boolean", "title": "Confirm"],
                        "urgency": [
                            "type": "string",
                            "oneOf": [
                                ["const": "normal", "title": "Normal"],
                                ["const": "urgent", "title": "Urgent"]
                            ],
                            "default": "normal"
                        ]
                    ],
                    "required": ["confirmed"]
                ],
                "_meta": ["traceID": "trace-1", "progressToken": "tool-progress"]
            ]
        ])

        XCTAssertEqual(envelope.id, .string("request-1"))
        guard case .form(let message, let schema, let metadata) = envelope.request else {
            return XCTFail("expected a typed form request")
        }
        XCTAssertEqual(message, "Confirm the calendar action")
        XCTAssertEqual(schema.objectValue?["type"], .string("object"))
        XCTAssertEqual(metadata, .object(["traceID": .string("trace-1")]))
    }

    func testLegacyStandardFormMayOmitMode() throws {
        let envelope = try MCPServerElicitationEnvelope.decode(from: [
            "id": 7,
            "method": "elicitation/create",
            "params": [
                "message": "Name this workspace",
                "requestedSchema": [
                    "type": "object",
                    "properties": ["name": ["type": "string", "minLength": 1]]
                ]
            ]
        ])
        XCTAssertEqual(envelope.id, .integer(7))
        guard case .form(let message, _, _) = envelope.request else {
            return XCTFail("expected a standard form request")
        }
        XCTAssertEqual(message, "Name this workspace")
    }

    func testTypedFormAcceptsExplicitNullsAllowedByCodexSchema() throws {
        let envelope = try MCPServerElicitationEnvelope.decode(from: [
            "id": 71,
            "method": "elicitation/create",
            "params": [
                "message": "Optional profile",
                "requestedSchema": [
                    "$schema": NSNull(),
                    "type": "object",
                    "properties": [
                        "email": [
                            "type": "string",
                            "format": NSNull(),
                            "default": NSNull()
                        ],
                        "role": [
                            "type": "string",
                            "enum": ["reader", "writer"],
                            "enumNames": NSNull()
                        ]
                    ],
                    "required": NSNull()
                ]
            ]
        ])
        guard case .form(_, let schema, _) = envelope.request else {
            return XCTFail("expected a standard form request")
        }
        XCTAssertEqual(schema.objectValue?["$schema"], .null)
        XCTAssertEqual(schema.objectValue?["required"], .null)
    }

    func testDecodesOpenAIFormAsOpaqueSchema() throws {
        let envelope = try MCPServerElicitationEnvelope.decode(from: [
            "id": 8,
            "method": "openai/form",
            "params": [
                "message": "Select an image",
                "requestedSchema": [
                    "type": "object",
                    "properties": [
                        "image": ["type": "openai/imagePicker", "items": []]
                    ]
                ]
            ]
        ])

        guard case .openAIForm(let message, let schema, _) = envelope.request else {
            return XCTFail("expected an OpenAI form request")
        }
        XCTAssertEqual(message, "Select an image")
        XCTAssertEqual(
            schema.objectValue?["properties"]?.objectValue?["image"]?.objectValue?["type"],
            .string("openai/imagePicker")
        )
    }

    func testDecodesURLElicitation() throws {
        let envelope = try MCPServerElicitationEnvelope.decode(from: [
            "id": 9,
            "method": "elicitation/create",
            "params": [
                "mode": "url",
                "message": "Authorize Calendar",
                "url": "https://example.com/authorize",
                "elicitationId": "oauth-1"
            ]
        ])

        XCTAssertEqual(
            envelope.request,
            .url(
                message: "Authorize Calendar",
                url: "https://example.com/authorize",
                elicitationID: "oauth-1",
                metadata: nil
            )
        )
    }

    func testTypedFormRejectsUnsupportedSchemaFields() {
        XCTAssertThrowsError(try MCPServerElicitationEnvelope.decode(from: [
            "id": 10,
            "method": "elicitation/create",
            "params": [
                "message": "Malformed",
                "requestedSchema": [
                    "type": "object",
                    "properties": [
                        "value": ["type": "string", "pattern": ".*"]
                    ]
                ]
            ]
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported field 'pattern'"))
        }
    }

    func testResponseOmitsContentForNonAcceptActions() {
        let response = MCPClientElicitationResponse(
            action: .decline,
            content: .object(["ignored": .bool(true)]),
            metadata: .object(["reason": .string("user")])
        )
        XCTAssertNil(response.content)
        XCTAssertEqual(response.foundationObject["action"] as? String, "decline")
        XCTAssertNil(response.foundationObject["content"])
        XCTAssertNotNil(response.foundationObject["_meta"])
    }

    func testAsyncBridgeReturnsHandlerResponse() throws {
        let request = MCPClientElicitationRequest.form(
            message: "Confirm",
            requestedSchema: .object(["type": .string("object"), "properties": .object([:])]),
            metadata: nil
        )
        let response = try MCPAsyncElicitationBridge.resolve(
            request,
            using: { _ in .accept(content: .object(["confirmed": .bool(true)])) },
            deadline: Date().addingTimeInterval(1)
        )
        XCTAssertEqual(response, .accept(content: .object(["confirmed": .bool(true)])))
    }

    func testAsyncBridgeCancelsAtDeadline() throws {
        let request = MCPClientElicitationRequest.form(
            message: "Confirm",
            requestedSchema: .object(["type": .string("object"), "properties": .object([:])]),
            metadata: nil
        )
        let response = try MCPAsyncElicitationBridge.resolve(
            request,
            using: { _ in
                try? await Task.sleep(for: .seconds(1))
                return .accept(content: .object([:]))
            },
            deadline: Date().addingTimeInterval(0.02)
        )
        XCTAssertEqual(response, .cancel())
    }
}
