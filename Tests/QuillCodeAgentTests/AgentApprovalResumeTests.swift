import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentApprovalResumeTests: XCTestCase {
    func testApprovedToolExecutesOnceAndResumesWithoutDuplicatingUserTurn() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "approved.txt", "content": "done"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Finished the approved write.")]),
            safety: StaticSafetyReviewer()
        )
        let thread = ChatThread(mode: .review)

        let paused = try await runner.send("Create the file", in: thread, workspaceRoot: root)

        let pending = try XCTUnwrap(paused.pendingApproval)
        XCTAssertEqual(pending.heldToolCall, call)
        XCTAssertEqual(paused.stopReason, .approvalRequired(requestID: pending.request.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("approved.txt").path))

        let resumed = try await runner.resumeApproved(
            pending,
            in: paused.thread,
            workspaceRoot: root,
            userMessage: "Create the file"
        )

        XCTAssertNil(resumed.pendingApproval)
        XCTAssertEqual(resumed.thread.messages.filter { $0.role == .user }.map(\.content), ["Create the file"])
        XCTAssertEqual(resumed.thread.messages.last?.content, "Finished the approved write.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("approved.txt").path))
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .approvalDecided }.count, 1)
        XCTAssertEqual(resumed.thread.events.filter { $0.kind == .toolCompleted }.count, 1)

        do {
            _ = try await runner.resumeApproved(
                pending,
                in: resumed.thread,
                workspaceRoot: root,
                userMessage: "Create the file"
            )
            XCTFail("A decided approval must not replay its held tool")
        } catch let error as AgentApprovalResumeError {
            XCTAssertEqual(error, .requestNotPending(pending.request.id))
        }
    }

    func testResumeRejectsApprovalMetadataThatDoesNotMatchTheTranscript() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "untouched.txt", "content": "no"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call)]),
            safety: StaticSafetyReviewer()
        )
        let paused = try await runner.send(
            "Create the file",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )
        var tampered = try XCTUnwrap(paused.pendingApproval)
        tampered.request.reason = "A different persisted request."

        do {
            _ = try await runner.resumeApproved(
                tampered,
                in: paused.thread,
                workspaceRoot: root,
                userMessage: "Create the file"
            )
            XCTFail("Mismatched approval metadata must not execute")
        } catch let error as AgentApprovalResumeError {
            XCTAssertEqual(error, .requestNotPending(tampered.request.id))
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("untouched.txt").path
        ))
    }
}
