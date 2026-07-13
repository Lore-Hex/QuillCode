import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceSubagentRelaunchReconcilerTests: XCTestCase {
    func testValidPendingApprovalSurvivesRelaunch() throws {
        let fixture = try makeFixture(phase: .pending)

        let result = WorkspaceSubagentRelaunchReconciler.reconcile(
            [fixture.parent],
            childStore: fixture.childStore,
            payloadStore: fixture.payloadStore
        )

        XCTAssertTrue(result.changedThreadIDs.isEmpty)
        XCTAssertEqual(result.threads[0].subagentRuns[0].workers[0].status, .awaitingApproval)
        XCTAssertEqual(result.threads[0].subagentRuns[0].workers[0].pendingApproval?.phase, .pending)
        XCTAssertNoThrow(try fixture.payloadStore.load(fixture.payloadKey))
    }

    func testExecutingApprovalBecomesInterruptedAndPayloadCannotReplay() throws {
        let fixture = try makeFixture(phase: .executing)

        let result = WorkspaceSubagentRelaunchReconciler.reconcile(
            [fixture.parent],
            childStore: fixture.childStore,
            payloadStore: fixture.payloadStore
        )

        XCTAssertEqual(result.changedThreadIDs, [fixture.parent.id])
        let worker = result.threads[0].subagentRuns[0].workers[0]
        XCTAssertEqual(worker.status, .interrupted)
        XCTAssertNil(worker.pendingApproval)
        XCTAssertThrowsError(try fixture.payloadStore.load(fixture.payloadKey))
    }

    func testChildDecisionAheadOfPendingManifestRecoversAsInterrupted() throws {
        let fixture = try makeFixture(phase: .pending, childAlreadyDecided: true)

        let result = WorkspaceSubagentRelaunchReconciler.reconcile(
            [fixture.parent],
            childStore: fixture.childStore,
            payloadStore: fixture.payloadStore
        )

        let worker = result.threads[0].subagentRuns[0].workers[0]
        XCTAssertEqual(worker.status, .interrupted)
        XCTAssertNil(worker.pendingApproval)
        XCTAssertThrowsError(try fixture.payloadStore.load(fixture.payloadKey))
    }

    func testRunningWorkerNeverRestartsImplicitlyAfterRelaunch() throws {
        let root = try makeQuillCodeTestDirectory()
        let childStore = SubagentThreadStore(directory: root.appendingPathComponent("children"))
        let payloadStore = SubagentApprovalPayloadStore(directory: root.appendingPathComponent("payloads"))
        let parent = ChatThread(subagentRuns: [SubagentRunRecord(
            objective: "mutate workspace",
            workers: [SubagentWorkerRecord(name: "Writer", role: "write", status: .running)]
        )])

        let result = WorkspaceSubagentRelaunchReconciler.reconcile(
            [parent],
            childStore: childStore,
            payloadStore: payloadStore
        )

        XCTAssertEqual(result.threads[0].subagentRuns[0].workers[0].status, .interrupted)
        XCTAssertNil(result.threads[0].subagentRuns[0].finishedAt)
    }

    private func makeFixture(
        phase: SubagentApprovalPhase,
        childAlreadyDecided: Bool = false
    ) throws -> RelaunchFixture {
        let root = try makeQuillCodeTestDirectory()
        let childStore = SubagentThreadStore(directory: root.appendingPathComponent("children"))
        let payloadStore = SubagentApprovalPayloadStore(directory: root.appendingPathComponent("payloads"))
        let childID = UUID()
        let payloadKey = UUID()
        let requestID = "approval-relaunch"
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: requestID,
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "Approval required."
        )
        var events = [ThreadEvent(
            kind: .approvalRequested,
            summary: request.reason,
            payloadJSON: try JSONHelpers.encodePretty(request)
        )]
        if childAlreadyDecided {
            events.append(ThreadEvent(
                kind: .approvalDecided,
                summary: "approve",
                payloadJSON: try JSONHelpers.encodePretty(ApprovalDecision(
                    requestID: requestID,
                    verdict: .approve,
                    rationale: "Approved."
                ))
            ))
        }
        try childStore.save(ChatThread(id: childID, events: events))
        try payloadStore.save(call, key: payloadKey)
        let worker = SubagentWorkerRecord(
            id: "worker",
            childThreadID: childID,
            name: "Worker",
            role: "run command",
            status: .awaitingApproval,
            pendingApproval: SubagentPendingApproval(
                requestID: requestID,
                generation: 1,
                payloadKey: payloadKey,
                phase: phase
            )
        )
        let parent = ChatThread(subagentRuns: [SubagentRunRecord(
            objective: "inspect user",
            workers: [worker]
        )])
        return RelaunchFixture(
            parent: parent,
            childStore: childStore,
            payloadStore: payloadStore,
            payloadKey: payloadKey
        )
    }
}

private struct RelaunchFixture {
    var parent: ChatThread
    var childStore: SubagentThreadStore
    var payloadStore: SubagentApprovalPayloadStore
    var payloadKey: UUID
}
