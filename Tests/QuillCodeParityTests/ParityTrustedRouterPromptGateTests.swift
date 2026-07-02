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
        // The client delegates prompt assembly to the builder; `assembled` is the entry point
        // that returns the messages plus the prefix-stability flag prompt caching needs.
        XCTAssertTrue(client.contains("promptBuilder.assembled"))

        XCTAssertFalse(client.contains("systemPrompt(tools"))
        XCTAssertFalse(client.contains("projectInstructionsPrompt"))
        XCTAssertFalse(client.contains("memoryPrompt"))
        XCTAssertFalse(client.contains("thread.messages.suffix"))
    }
}
