import XCTest

final class ParityTrustedRouterChatParametersGateTests: QuillCodeParityTestCase {
    func testTrustedRouterChatParametersLiveOutsideTransportClients() throws {
        let client = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClient = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let parameters = try Self.agentSourceText(named: "TrustedRouterChatParameters.swift")

        XCTAssertTrue(parameters.contains("public enum TrustedRouterChatParameters"))
        XCTAssertTrue(parameters.contains("\"response_format\""))
        XCTAssertTrue(client.contains("TrustedRouterChatParameters.jsonObjectResponse"))
        XCTAssertTrue(safetyClient.contains("TrustedRouterChatParameters.jsonObjectResponse"))

        XCTAssertFalse(client.contains("\"response_format\""))
        XCTAssertFalse(safetyClient.contains("\"response_format\""))
        XCTAssertFalse(safetyClient.contains("TrustedRouterLLMClient."))
    }
}
