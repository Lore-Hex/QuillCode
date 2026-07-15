import Foundation
import XCTest
@testable import QuillCodeCore

final class QuillCodePersonalityTests: XCTestCase {
    func testPersonalityParsingIsWhitespaceAndCaseInsensitive() {
        XCTAssertEqual(QuillCodePersonality.parse(" Friendly \n"), .friendly)
        XCTAssertEqual(QuillCodePersonality.parse("PRAGMATIC"), .pragmatic)
        XCTAssertEqual(
            QuillCodePersonality.parse("none"),
            Optional.some(QuillCodePersonality.none)
        )
        XCTAssertNil(QuillCodePersonality.parse("verbose"))
    }

    func testOlderConfigAndThreadPayloadsUsePragmaticDefault() throws {
        let config = try decodeAfterRemoving(
            AppConfig(defaultPersonality: .friendly),
            key: "defaultPersonality"
        )
        let thread = try decodeAfterRemoving(
            ChatThread(personality: .friendly),
            key: "personality"
        )

        XCTAssertEqual(config.defaultPersonality, .pragmatic)
        XCTAssertEqual(thread.personality, .pragmatic)
    }

    func testConfigAndThreadRoundTripEveryPersonality() throws {
        for personality in QuillCodePersonality.allCases {
            let config = AppConfig(defaultPersonality: personality)
            let thread = ChatThread(personality: personality)

            XCTAssertEqual(try roundTrip(config).defaultPersonality, personality)
            XCTAssertEqual(try roundTrip(thread).personality, personality)
        }
    }

    func testModelTreatsOnlyExplicitFalseAsUnsupported() {
        let unknown = ModelInfo(
            id: "provider/unknown",
            provider: "provider",
            displayName: "Unknown",
            category: "Test"
        )
        let supported = ModelInfo(
            id: "provider/supported",
            provider: "provider",
            displayName: "Supported",
            category: "Test",
            capabilities: ModelCapabilities(supportsPersonality: true)
        )
        let unsupported = ModelInfo(
            id: "provider/unsupported",
            provider: "provider",
            displayName: "Unsupported",
            category: "Test",
            capabilities: ModelCapabilities(supportsPersonality: false)
        )

        XCTAssertTrue(unknown.supportsPersonality)
        XCTAssertTrue(supported.supportsPersonality)
        XCTAssertFalse(unsupported.supportsPersonality)
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func decodeAfterRemoving<Value: Codable>(_ value: Value, key: String) throws -> Value {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: key)
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
