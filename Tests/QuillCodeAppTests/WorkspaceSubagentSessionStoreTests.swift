import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSubagentSessionStoreTests: XCTestCase {
    func testStoreRoundTripsExactPrivateContinuationWhilePublicUpdateStaysRedacted() throws {
        let directory = try makeTempDirectory().appendingPathComponent("subagent-sessions")
        let store = WorkspaceSubagentSessionStore(directory: directory)
        let secret = "sk-SYNTHETIC_SUBAGENT_SESSION_SECRET_123456"
        let exactCall = ToolCall(
            name: "host.shell.run",
            argumentsJSON: ToolArguments.json([
                "cmd": "printenv TOKEN",
                "environment": ["TOKEN": secret]
            ])
        )
        let request = ApprovalRequest(
            toolCall: exactCall.redactedForTranscript(),
            toolDefinition: nil,
            reason: "Confirm environment inspection."
        )
        var child = ChatThread(title: "Subagent: Inspector")
        child.events.append(.init(
            kind: .approvalRequested,
            summary: request.reason,
            payloadJSON: try JSONHelpers.encodePretty(request)
        ))
        let runID = UUID().uuidString
        let gate = SubagentApprovalGate(
            runID: runID,
            requestID: request.id,
            toolName: exactCall.name,
            reason: request.reason
        )
        let state = WorkspaceSubagentRunState(
            id: runID,
            objective: "Inspect safely",
            maxConcurrentWorkers: 1,
            jobs: [WorkspaceSubagentJob(name: "Inspector", role: "inspect")],
            items: [SubagentProgressItem(
                name: "Inspector",
                role: "inspect",
                status: .awaitingApproval,
                summary: "Needs approval",
                approvalGate: gate
            )],
            pausedWorkers: [
                "Inspector": WorkspaceSubagentApprovalPause(
                    prompt: "Inspect safely",
                    thread: child,
                    pendingApproval: AgentPendingApproval(request: request, heldToolCall: exactCall)
                )
            ]
        )

        try store.save(WorkspaceSubagentSessionRecord(parentThreadID: UUID(), state: state))
        let restored = try store.load(runID)
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        )
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        ).intValue
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        ).intValue

        XCTAssertEqual(
            restored.state.pausedWorkers["Inspector"]?.pendingApproval.heldToolCall,
            exactCall
        )
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
        let publicJSON = try JSONHelpers.encodePretty(SubagentProgressUpdate(
            objective: restored.state.objective,
            subagents: restored.state.items
        ))
        XCTAssertFalse(publicJSON.contains(secret))
        XCTAssertFalse(publicJSON.contains("printenv TOKEN"))

        try store.delete(runID)
        XCTAssertThrowsError(try store.load(runID))
    }
}
