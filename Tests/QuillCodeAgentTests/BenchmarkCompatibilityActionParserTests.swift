import Foundation
import QuillCodeCore
import XCTest
@testable import QuillCodeAgent

final class BenchmarkCompatibilityActionParserTests: XCTestCase {
    func testParsesTAU3BankingToolAction() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"verify_customer","arguments":{"customer_id":"c_1001","last4":"2719"}}
        """)
        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, "verify_customer")
        let arguments = try argumentsObject(call.argumentsJSON)
        XCTAssertEqual(arguments["customer_id"] as? String, "c_1001")
        XCTAssertEqual(arguments["last4"] as? String, "2719")
    }

    func testParsesBFCLFunctionEnvelopeWithStringArguments() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"function_call","function":{"name":"get_weather","arguments":"{\\"location\\":\\"Berkeley, CA\\",\\"unit\\":\\"celsius\\"}"}}
        """)
        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, "get_weather")
        let arguments = try argumentsObject(call.argumentsJSON)
        XCTAssertEqual(arguments["location"] as? String, "Berkeley, CA")
        XCTAssertEqual(arguments["unit"] as? String, "celsius")
    }

    func testParsesDeepSeekShorthandToolAction() throws {
        let action = try AgentActionJSONParser.parse("""
        {"name":"freeze_card","arguments":{"card_id":"card_1001"}}
        """)
        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, "freeze_card")
        let arguments = try argumentsObject(call.argumentsJSON)
        XCTAssertEqual(arguments["card_id"] as? String, "card_1001")
    }

    private func argumentsObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
