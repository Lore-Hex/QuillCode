import XCTest

final class ParityTrustedRouterSafetyTransportGateTests: QuillCodeParityTestCase {
    func testTrustedRouterSafetyClientLivesOutsideActionTransportFile() throws {
        let client = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClient = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")

        XCTAssertTrue(safetyClient.contains("public struct TrustedRouterSafetyModelClient"))
        XCTAssertTrue(safetyClient.contains("SafetyModelClient"))
        XCTAssertTrue(safetyClient.contains("Return only the requested JSON object."))

        XCTAssertFalse(client.contains("TrustedRouterSafetyModelClient"))
        XCTAssertFalse(client.contains("SafetyModelClient"))
    }
}
