@testable import QuillCodeCLI
import QuillCodeCore
import XCTest

final class MCPServerConfigOverlayTests: XCTestCase {
    func testResolvesCodexAliasesAndExplicitPolicyPrecedence() throws {
        let input = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "approval-policy": .string("on-request"),
            "config": .object([
                "model": .string("provider/model"),
                "max_tool_steps": .number(17),
                "api_base_url": .string("https://example.test/v1")
            ])
        ])
        let resolved = try MCPServerConfigOverlay.resolve(
            input: input,
            base: AppConfig(mode: .auto),
            serverModel: nil
        )
        XCTAssertEqual(resolved.model, "provider/model")
        XCTAssertEqual(resolved.appConfig.maxToolSteps, 17)
        XCTAssertEqual(resolved.appConfig.apiBaseURL, "https://example.test/v1")
        XCTAssertEqual(resolved.approvalsReviewer, "user")
        XCTAssertEqual(resolved.sandbox, .workspaceWrite)
    }

    func testRejectsUnknownConfigAndNonTrustedRouterProvider() throws {
        let unknown = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "config": .object(["mystery": .bool(true)])
        ])
        XCTAssertThrowsError(try MCPServerConfigOverlay.resolve(
            input: unknown,
            base: AppConfig(),
            serverModel: nil
        ))

        let provider = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "config": .object(["model_provider": .string("other")])
        ])
        XCTAssertThrowsError(try MCPServerConfigOverlay.resolve(
            input: provider,
            base: AppConfig(),
            serverModel: nil
        ))
    }
}
