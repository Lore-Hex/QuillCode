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

    func testMessagesIncludeProjectInstructionsAsSystemContext() {
        let thread = ChatThread(
            messages: [.init(role: .user, content: "status")],
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "Project AGENTS.md",
                    content: "Always run swift test before claiming completion.",
                    byteCount: 52
                ),
                ProjectInstruction(
                    path: "Sources/Feature/AGENTS.md",
                    title: "Sources/Feature/AGENTS.md",
                    content: "Prefer feature-scoped tests for feature code.",
                    byteCount: 42
                )
            ]
        )

        let messages = TrustedRouterLLMClient.messages(
            thread: thread,
            userMessage: "run tests",
            tools: [.shellRun]
        )

        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "system")
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("AGENTS.md") == true)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("broadest to most specific") == true)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("Sources/Feature/AGENTS.md") == true)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("Always run swift test") == true)
    }

    func testModelCatalogMapsProvidersAndCategories() {
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "z-ai/glm-5.2" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "moonshotai/kimi-k2.6" })
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
