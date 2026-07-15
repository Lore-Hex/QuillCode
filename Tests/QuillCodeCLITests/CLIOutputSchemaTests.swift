import Foundation
@testable import QuillCodeCLI
import XCTest

final class CLIOutputSchemaTests: XCTestCase {
    func testValidatesCommonObjectSchemaAndFencedJSON() throws {
        let schema = try loadSchema("""
        {
          "type": "object",
          "properties": {
            "name": {"type": "string", "minLength": 2},
            "count": {"type": "integer", "minimum": 1},
            "tags": {"type": "array", "items": {"type": "string"}, "uniqueItems": true}
          },
          "required": ["name", "count"],
          "additionalProperties": false
        }
        """)
        XCTAssertNoThrow(try schema.validate(finalMessage: """
        ```json
        {"name":"QuillCode","count":2,"tags":["swift","cli"]}
        ```
        """))
    }

    func testRejectsMissingWrongAndAdditionalProperties() throws {
        let schema = try loadSchema("""
        {
          "type": "object",
          "properties": {"name": {"type": "string"}, "count": {"type": "integer"}},
          "required": ["name", "count"],
          "additionalProperties": false
        }
        """)
        XCTAssertThrowsError(try schema.validate(finalMessage: "{\"name\":\"x\"}"))
        XCTAssertThrowsError(try schema.validate(finalMessage: "{\"name\":\"x\",\"count\":1.5}"))
        XCTAssertThrowsError(try schema.validate(
            finalMessage: "{\"name\":\"x\",\"count\":1,\"extra\":true}"
        ))
    }

    func testResolvesLocalDefinitionsAndCombinators() throws {
        let schema = try loadSchema("""
        {
          "$defs": {"id": {"type": "string", "pattern": "^[a-z]+$"}},
          "type": "object",
          "properties": {
            "id": {"$ref": "#/$defs/id"},
            "value": {"oneOf": [{"type":"string"},{"type":"number"}]}
          },
          "required": ["id", "value"]
        }
        """)
        XCTAssertNoThrow(try schema.validate(finalMessage: "{\"id\":\"abc\",\"value\":3}"))
        XCTAssertThrowsError(try schema.validate(finalMessage: "{\"id\":\"123\",\"value\":true}"))
    }

    func testRejectsInvalidAndOversizedSchemaFiles() throws {
        let invalid = try temporaryFile(contents: "[]")
        XCTAssertThrowsError(try CLIOutputSchema.load(from: invalid))

        let oversized = try temporaryFile(
            data: Data(repeating: 32, count: CLIOutputSchema.maximumBytes + 1)
        )
        XCTAssertThrowsError(try CLIOutputSchema.load(from: oversized))
    }

    private func loadSchema(_ text: String) throws -> CLIOutputSchema {
        try CLIOutputSchema.load(from: temporaryFile(contents: text))
    }

    private func temporaryFile(contents: String) throws -> URL {
        try temporaryFile(data: Data(contents.utf8))
    }

    private func temporaryFile(data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-schema-\(UUID().uuidString).json")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
