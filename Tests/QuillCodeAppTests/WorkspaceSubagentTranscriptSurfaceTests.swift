import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

final class WorkspaceSubagentTranscriptSurfaceTests: XCTestCase {
    func testLoaderBuildsExactApprovalActionsForTheDurableChild() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = SubagentThreadStore(directory: directory)
        let childID = UUID()
        let request = ApprovalRequest(
            id: "child-approval",
            toolCall: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: "{\"cmd\":\"whoami\"}"),
            toolDefinition: ToolDefinition.shellRun,
            reason: "Confirm the delegated command."
        )
        let child = ChatThread(
            id: childID,
            title: "Verifier",
            messages: [ChatMessage(role: .user, content: "Verify the current user.")],
            events: [ThreadEvent(
                kind: .approvalRequested,
                summary: request.reason,
                payloadJSON: try JSONHelpers.encodePretty(request)
            )]
        )
        try store.save(child)

        let runID = UUID()
        let worker = SubagentWorkerRecord(
            id: "verifier-worker",
            childThreadID: childID,
            name: "Verifier",
            role: "inspect identity",
            status: .awaitingApproval,
            pendingApproval: SubagentPendingApproval(
                requestID: request.id,
                generation: 3
            )
        )
        let parent = ChatThread(
            id: UUID(),
            subagentRuns: [SubagentRunRecord(
                id: runID,
                objective: "Verify the runtime",
                workers: [worker]
            )]
        )

        let surface = try XCTUnwrap(WorkspaceSubagentTranscriptLoader.load(
            parentThread: parent,
            runID: runID,
            workerID: worker.id,
            store: store
        ))
        let card = try XCTUnwrap(surface.transcript.toolCards.first)

        XCTAssertEqual(surface.status, .awaitingApproval)
        XCTAssertEqual(card.actions.map(\.kind), [.approve, .deny])
        XCTAssertTrue(card.actions.allSatisfy { action in
            action.subagentTarget == WorkspaceSubagentApprovalTarget(
                parentThreadID: parent.id,
                runID: runID,
                workerID: worker.id,
                generation: 3
            )
        })
    }

    func testLoaderRejectsUnknownRunBeforeReadingAChildTranscript() throws {
        let store = SubagentThreadStore(directory: try makeQuillCodeTestDirectory())
        let parent = ChatThread(
            subagentRuns: [SubagentRunRecord(
                objective: "Known run",
                workers: [SubagentWorkerRecord(name: "Worker", role: "inspect")]
            )]
        )

        XCTAssertNil(try WorkspaceSubagentTranscriptLoader.load(
            parentThread: parent,
            runID: UUID(),
            workerID: "unknown",
            store: store
        ))
    }
}
