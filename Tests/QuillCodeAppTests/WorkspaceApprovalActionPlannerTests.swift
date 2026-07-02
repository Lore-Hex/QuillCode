import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceApprovalActionPlannerTests: XCTestCase {
    func testApprovePlanUsesLatestMatchingRequestAndBuildsDecisionEvent() throws {
        let oldRequest = approvalRequest(
            id: "approval-1",
            call: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json(["cmd": "pwd"]))
        )
        let latestRequest = approvalRequest(
            id: "approval-1",
            call: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json(["cmd": "whoami"])),
            reviewTelemetry: ApprovalReviewTelemetry(
                source: .fallbackModel,
                reviewerModel: "kimi-k2.6",
                attemptedModels: ["glm-5.2", "kimi-k2.6"],
                fallbackReason: .primaryModelFailed,
                errorSummary: "primary unavailable"
            )
        )
        let thread = ChatThread(events: [
            try approvalRequestedEvent(oldRequest),
            ThreadEvent(kind: .approvalRequested, summary: "bad payload", payloadJSON: "{"),
            try approvalRequestedEvent(latestRequest)
        ])

        let plan = try XCTUnwrap(WorkspaceApprovalActionPlanner.plan(
            action: ToolCardActionSurface(title: "Run", kind: .approve, requestID: "approval-1", style: .primary),
            thread: thread
        ))
        let decision = try JSONHelpers.decode(
            ApprovalDecision.self,
            from: try XCTUnwrap(plan.decisionEvent?.payloadJSON)
        )

        XCTAssertEqual(plan.request.toolCall.argumentsJSON, ToolArguments.json(["cmd": "whoami"]))
        XCTAssertTrue(plan.shouldRunTool)
        XCTAssertNil(plan.assistantNotice)
        XCTAssertEqual(plan.decisionEvent?.kind, .approvalDecided)
        XCTAssertEqual(plan.decisionEvent?.summary, "approve: Approved from the tool card.")
        XCTAssertNil(plan.composerDraft)
        XCTAssertEqual(decision.requestID, "approval-1")
        XCTAssertEqual(decision.verdict, .approve)
        XCTAssertEqual(decision.rationale, "Approved from the tool card.")
        XCTAssertEqual(decision.reviewTelemetry, latestRequest.reviewTelemetry)
    }

    func testDenyPlanBuildsSkipNoticeAndDenyDecision() throws {
        let request = approvalRequest(
            id: "approval-skip",
            call: ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: ToolArguments.json([
                "path": "hello.txt",
                "content": "hello"
            ]))
        )
        let thread = ChatThread(events: [try approvalRequestedEvent(request)])

        let plan = try XCTUnwrap(WorkspaceApprovalActionPlanner.plan(
            action: ToolCardActionSurface(title: "Skip", kind: .deny, requestID: "approval-skip", style: .secondary),
            thread: thread
        ))
        let decision = try JSONHelpers.decode(
            ApprovalDecision.self,
            from: try XCTUnwrap(plan.decisionEvent?.payloadJSON)
        )

        XCTAssertFalse(plan.shouldRunTool)
        XCTAssertEqual(plan.assistantNotice, "Skipped \(ToolDefinition.fileWrite.name).")
        XCTAssertNil(plan.composerDraft)
        XCTAssertEqual(plan.decisionEvent?.summary, "deny: Skipped from the tool card.")
        XCTAssertEqual(decision.verdict, .deny)
        XCTAssertEqual(decision.rationale, "Skipped from the tool card.")
    }

    func testEditPlanLoadsShellCommandDraftWithoutRecordingDecision() throws {
        let request = approvalRequest(
            id: "approval-edit",
            call: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json(["cmd": "ls -la"]))
        )
        let thread = ChatThread(events: [try approvalRequestedEvent(request)])

        let plan = try XCTUnwrap(WorkspaceApprovalActionPlanner.plan(
            action: ToolCardActionSurface(title: "Edit", kind: .edit, requestID: "approval-edit", style: .secondary),
            thread: thread
        ))

        XCTAssertFalse(plan.shouldRunTool)
        XCTAssertNil(plan.decisionEvent)
        XCTAssertNil(plan.assistantNotice)
        XCTAssertEqual(plan.composerDraft, "Run ls -la")
    }

    func testEditPlanLoadsGenericToolDraftForNonShellCalls() throws {
        let request = approvalRequest(
            id: "approval-edit-file",
            call: ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: ToolArguments.json([
                "path": "hello.txt",
                "content": "hello"
            ]))
        )
        let thread = ChatThread(events: [try approvalRequestedEvent(request)])

        let plan = try XCTUnwrap(WorkspaceApprovalActionPlanner.plan(
            action: ToolCardActionSurface(title: "Edit", kind: .edit, requestID: "approval-edit-file", style: .secondary),
            thread: thread
        ))

        XCTAssertFalse(plan.shouldRunTool)
        XCTAssertNil(plan.decisionEvent)
        XCTAssertEqual(plan.composerDraft, """
        Revise and run \(ToolDefinition.fileWrite.name) with arguments:
        \(ToolArguments.json(["path": "hello.txt", "content": "hello"]))
        """)
    }

    func testPlanReturnsNilWhenRequestIsMissingOrInvalid() throws {
        let action = ToolCardActionSurface(title: "Run", kind: .approve, requestID: "missing", style: .primary)
        let invalidThread = ChatThread(events: [
            ThreadEvent(kind: .approvalRequested, summary: "bad payload", payloadJSON: "{")
        ])

        XCTAssertNil(WorkspaceApprovalActionPlanner.plan(action: action, thread: nil))
        XCTAssertNil(WorkspaceApprovalActionPlanner.plan(action: action, thread: invalidThread))
    }

    private func approvalRequest(
        id: String,
        call: ToolCall,
        reviewTelemetry: ApprovalReviewTelemetry? = nil
    ) -> ApprovalRequest {
        ApprovalRequest(
            id: id,
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required",
            reviewTelemetry: reviewTelemetry
        )
    }

    private func approvalRequestedEvent(_ request: ApprovalRequest) throws -> ThreadEvent {
        ThreadEvent(
            kind: .approvalRequested,
            summary: "review required",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
    }
}
