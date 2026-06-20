import XCTest
@testable import QuillCodeCore

final class CoreModelTests: XCTestCase {
    func testTrustedRouterDefaults() {
        XCTAssertEqual(TrustedRouterDefaults.defaultModel, "trustedrouter/fusion")
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
    }
}
