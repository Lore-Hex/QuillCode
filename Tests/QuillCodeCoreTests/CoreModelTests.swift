import XCTest
@testable import QuillCodeCore

final class CoreModelTests: XCTestCase {
    func testTrustedRouterDefaults() {
        XCTAssertEqual(TrustedRouterDefaults.fastModel, "trustedrouter/fast")
        XCTAssertEqual(TrustedRouterDefaults.fusionModel, "trustedrouter/fusion")
        XCTAssertEqual(TrustedRouterDefaults.defaultModel, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.safetyPrimaryModel, "glm-5.2")
        XCTAssertEqual(TrustedRouterDefaults.safetyFallbackModel, "kimi-k2.6")
    }

    func testToolCallRoundTrips() throws {
        let call = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"whoami"}"#)
        let encoded = try JSONHelpers.encodePretty(call)
        let decoded = try JSONHelpers.decode(ToolCall.self, from: encoded)
        XCTAssertEqual(decoded.name, call.name)
        XCTAssertEqual(decoded.argumentsJSON, call.argumentsJSON)
    }

    func testToolArgumentsRejectMissingCommand() throws {
        let args = try ToolArguments("{}")
        XCTAssertThrowsError(try args.requiredString("cmd"))
    }

    func testToolArgumentsParseIntegerValues() throws {
        let args = try ToolArguments(#"{"x":42,"y":"84"}"#)

        XCTAssertEqual(try args.requiredInt("x"), 42)
        XCTAssertEqual(try args.requiredInt("y"), 84)
        XCTAssertThrowsError(try args.requiredInt("z"))
    }

    func testAppConfigDecodesOlderPayloadWithoutFavorites() throws {
        let config = try JSONHelpers.decode(AppConfig.self, from: """
        {
          "defaultModel": "trustedrouter/fusion",
          "mode": "auto",
          "apiBaseURL": "https://api.trustedrouter.com/v1",
          "authMode": "oauth",
          "developerOverrideEnabled": false
        }
        """)

        XCTAssertEqual(config.defaultModel, "trustedrouter/fusion")
        XCTAssertEqual(config.favoriteModels, [])
    }

    func testProjectAndThreadDecodeOlderStateWithoutInstructions() throws {
        let projectID = UUID()
        let date = ISO8601DateFormatter().string(from: Date())
        let project = try JSONHelpers.decode(ProjectRef.self, from: """
        {
          "id": "\(projectID.uuidString)",
          "name": "QuillCode",
          "path": "/tmp/QuillCode",
          "lastOpenedAt": "\(date)"
        }
        """)
        XCTAssertEqual(project.instructions, [])
        XCTAssertEqual(project.localActions, [])
        XCTAssertEqual(project.memories, [])

        let threadID = UUID()
        let thread = try JSONHelpers.decode(ChatThread.self, from: """
        {
          "id": "\(threadID.uuidString)",
          "title": "Old thread",
          "projectID": "\(projectID.uuidString)",
          "mode": "auto",
          "model": "trustedrouter/fusion",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "\(date)",
          "updatedAt": "\(date)"
        }
        """)
        XCTAssertEqual(thread.instructions, [])
        XCTAssertEqual(thread.memories, [])
    }
}
