import XCTest

final class ParityTrustedRouterChatParametersGateTests: QuillCodeParityTestCase {
    func testTrustedRouterChatParametersLiveOutsideTransportClients() throws {
        let client = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClient = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let parameters = try Self.agentSourceText(named: "TrustedRouterChatParameters.swift")

        XCTAssertTrue(parameters.contains("public enum TrustedRouterChatParameters"))
        XCTAssertTrue(parameters.contains("\"response_format\""))
        XCTAssertTrue(parameters.contains("agentActionResponse(model:"))
        XCTAssertTrue(parameters.contains("\"reasoning_effort\""))
        XCTAssertTrue(client.contains("TrustedRouterChatParameters.agentActionResponse(model: model)"))
        XCTAssertTrue(safetyClient.contains("TrustedRouterChatParameters.jsonObjectResponse"))

        XCTAssertFalse(client.contains("\"response_format\""))
        XCTAssertFalse(safetyClient.contains("\"response_format\""))
        XCTAssertFalse(safetyClient.contains("TrustedRouterLLMClient."))
    }
}
