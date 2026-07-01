import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceModelVerificationGateTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        var value: AgentRunNotification?
    }

    private let verifyAction = LocalEnvironmentAction(id: "test", title: "Test", relativePath: ".", command: "swift test")

    private func editThread() -> ChatThread {
        let call = ToolCall(name: ToolDefinition.applyPatch.name, argumentsJSON: ToolArguments.json(["patch": "P"]))
        let payload = (try? JSONHelpers.encodePretty(call.redactedForTranscript())) ?? "{}"
        return ChatThread(
            title: "Fix bug",
            messages: [],
            events: [ThreadEvent(kind: .toolQueued, summary: "apply_patch queued", payloadJSON: payload)]
        )
    }

    private func verdictKind(from result: ToolResult) async throws -> AgentRunNotification.Kind? {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        model.verificationRunner = { _, _ in result }
        let box = Box()
        // The gate (notifyRunFinishedIfNeeded) only reaches here with a real verify action captured, so
        // the run-and-post is driven with the action directly — a gate that passes guarantees a notice.
        await model.runVerificationAndNotify(
            action: verifyAction,
            thread: editThread(),
            localActions: [verifyAction],
            workspaceRoot: root,
            handler: { box.value = $0 }
        )
        return box.value?.kind
    }

    func testPassedRunReportsVerifiedGreen() async throws {
        let kind = try await verdictKind(from: ToolResult(ok: true, stdout: "All good", stderr: "", exitCode: 0, error: nil))
        XCTAssertEqual(kind, .verifiedGreen)
    }

    func testFailingRunReportsChecksFailing() async throws {
        let kind = try await verdictKind(from: ToolResult(ok: false, stdout: "Executed 10 tests, with 3 failures", stderr: "", exitCode: 1, error: nil))
        XCTAssertEqual(kind, .checksFailing)
    }

    func testTimeoutReportsChecksFailing() async throws {
        let kind = try await verdictKind(from: ToolResult(ok: false, stdout: "", stderr: "", exitCode: nil, error: "Command timed out after 120s."))
        XCTAssertEqual(kind, .checksFailing)
    }
}
