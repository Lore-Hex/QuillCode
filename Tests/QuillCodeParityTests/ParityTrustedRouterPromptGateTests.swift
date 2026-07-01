import XCTest

final class ParityTrustedRouterPromptGateTests: QuillCodeParityTestCase {
    func testTrustedRouterPromptBuilderLivesOutsideTransportClient() throws {
        let client = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let builder = try Self.agentSourceText(named: "TrustedRouterPromptBuilder.swift")

        XCTAssertTrue(builder.contains("public struct TrustedRouterPromptBuilder"))
        XCTAssertTrue(builder.contains("historyLimit"))
        XCTAssertTrue(builder.contains("systemPrompt(tools"))
        XCTAssertTrue(builder.contains("projectInstructionsPrompt"))
        XCTAssertTrue(builder.contains("memoryPrompt"))
        XCTAssertTrue(client.contains("promptBuilder.messages"))

        XCTAssertFalse(client.contains("systemPrompt(tools"))
        XCTAssertFalse(client.contains("projectInstructionsPrompt"))
        XCTAssertFalse(client.contains("memoryPrompt"))
        XCTAssertFalse(client.contains("thread.messages.suffix"))
    }
}
