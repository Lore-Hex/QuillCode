import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class TrustedRouterAdapterTests: XCTestCase {
    func testActionParserParsesShellTool() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}
        """)
        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, "host.shell.run")
        XCTAssertTrue(call.argumentsJSON.contains("whoami"))
    }

    func testActionParserRejectsEmptyShellArguments() {
        XCTAssertThrowsError(try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.shell.run","arguments":{}}
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("empty argument"))
        }
    }

    func testActionParserParsesSay() throws {
        let action = try AgentActionJSONParser.parse(#"{"type":"say","text":"hello"}"#)
        XCTAssertEqual(action, .say("hello"))
    }

    func testPromptRequiresNonEmptyShellCommand() {
        let prompt = TrustedRouterLLMClient.systemPrompt(tools: [.shellRun, .fileWrite])
        XCTAssertTrue(prompt.contains("MUST include a non-empty \"cmd\""))
        XCTAssertTrue(prompt.contains("Do not say \"I'll do it\""))
    }

    func testModelCatalogMapsProvidersAndCategories() {
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "z-ai/glm-5.2"), "z-ai")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "trustedrouter/fusion", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "moonshotai/kimi-k2.6", provider: "moonshotai"), "Safety")
    }

    func testMissingAPIKeyIsActionable() {
        let client = TrustedRouterLLMClient()
        XCTAssertThrowsError(try client.configuredAPIKey()) { error in
            XCTAssertTrue(String(describing: error).contains("Sign in"))
        }
    }
}
