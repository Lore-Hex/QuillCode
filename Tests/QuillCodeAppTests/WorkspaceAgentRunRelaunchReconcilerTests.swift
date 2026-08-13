import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceAgentRunRelaunchReconcilerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testInterruptedOpenToolBecomesFailedAndRetryable() {
        let checkpoint = ThreadRunCheckpoint(messageCountAtStart: 1, eventCountAtStart: 1)
        let thread = ChatThread(
            messages: [.init(role: .user, content: "Run a long command")],
            events: [
                .init(kind: .message, summary: "Run a long command"),
                .init(kind: .toolQueued, summary: "host.shell.run queued"),
                .init(kind: .toolRunning, summary: "host.shell.run running")
            ],
            activeRunCheckpoint: checkpoint
        )

        let result = WorkspaceAgentRunRelaunchReconciler.reconcile([thread], now: now)
        let recovered = result.threads[0]

        XCTAssertEqual(result.changedThreadIDs, [thread.id])
        XCTAssertEqual(result.interruptedThreadIDs, [thread.id])
        XCTAssertNil(recovered.activeRunCheckpoint)
        XCTAssertEqual(recovered.events.suffix(2).map(\.kind), [.toolFailed, .notice])
        XCTAssertEqual(recovered.events.last?.summary, WorkspaceRunFailureNoticePlanner.interruptedRelaunchSummary)
        XCTAssertTrue(QuillCodeWorkspaceModel.lastRunFailed(in: recovered))
    }

    func testRunningOrProgressBoundaryWithoutQueuedEventStillBecomesFailed() {
        for kind in [ThreadEventKind.toolRunning, .toolProgress] {
            let thread = ChatThread(
                events: [.init(kind: kind, summary: "host.shell.run active")],
                activeRunCheckpoint: ThreadRunCheckpoint(
                    messageCountAtStart: 0,
                    eventCountAtStart: 0
                )
            )

            let result = WorkspaceAgentRunRelaunchReconciler.reconcile([thread], now: now)

            XCTAssertEqual(result.threads[0].events.suffix(2).map(\.kind), [.toolFailed, .notice])
        }
    }

    func testCompletedAssistantTurnClearsCheckpointSilently() {
        let checkpoint = ThreadRunCheckpoint(messageCountAtStart: 1, eventCountAtStart: 0)
        let thread = ChatThread(
            messages: [
                .init(role: .user, content: "Question"),
                .init(role: .assistant, content: "Answer")
            ],
            activeRunCheckpoint: checkpoint
        )

        let result = WorkspaceAgentRunRelaunchReconciler.reconcile([thread], now: now)

        XCTAssertEqual(result.changedThreadIDs, [thread.id])
        XCTAssertTrue(result.interruptedThreadIDs.isEmpty)
        XCTAssertNil(result.threads[0].activeRunCheckpoint)
        XCTAssertTrue(result.threads[0].events.isEmpty)
    }

    func testUndecidedApprovalClearsCheckpointAndPreservesGate() throws {
        let request = ApprovalRequest(
            id: "approval-1",
            toolCall: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: #"{"cmd":"whoami"}"#),
            toolDefinition: ToolDefinition.shellRun,
            reason: "Approval required"
        )
        let thread = ChatThread(
            events: [.init(
                kind: .approvalRequested,
                summary: request.reason,
                payloadJSON: try JSONHelpers.encodePretty(request)
            )],
            activeRunCheckpoint: ThreadRunCheckpoint(messageCountAtStart: 0, eventCountAtStart: 0)
        )

        let result = WorkspaceAgentRunRelaunchReconciler.reconcile([thread], now: now)

        XCTAssertTrue(result.interruptedThreadIDs.isEmpty)
        XCTAssertNil(result.threads[0].activeRunCheckpoint)
        XCTAssertEqual(result.threads[0].events, thread.events)
    }

    func testDecidedApprovalWithoutAnswerIsInterrupted() throws {
        let requestID = "approval-1"
        let request = ApprovalRequest(
            id: requestID,
            toolCall: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: #"{"cmd":"whoami"}"#),
            toolDefinition: ToolDefinition.shellRun,
            reason: "Approval required"
        )
        let decision = ApprovalDecision(
            requestID: requestID,
            verdict: .approve,
            rationale: "Approved"
        )
        let thread = ChatThread(
            events: [
                .init(kind: .approvalRequested, summary: request.reason, payloadJSON: try JSONHelpers.encodePretty(request)),
                .init(kind: .approvalDecided, summary: decision.rationale, payloadJSON: try JSONHelpers.encodePretty(decision))
            ],
            activeRunCheckpoint: ThreadRunCheckpoint(messageCountAtStart: 0, eventCountAtStart: 0)
        )

        let result = WorkspaceAgentRunRelaunchReconciler.reconcile([thread], now: now)

        XCTAssertEqual(result.interruptedThreadIDs, [thread.id])
        XCTAssertEqual(result.threads[0].events.last?.kind, .notice)
    }

    func testReconciliationIsIdempotentAndBoundsOversizedOffsets() {
        let thread = ChatThread(activeRunCheckpoint: ThreadRunCheckpoint(
            messageCountAtStart: Int.max,
            eventCountAtStart: Int.max
        ))

        let first = WorkspaceAgentRunRelaunchReconciler.reconcile([thread], now: now)
        let second = WorkspaceAgentRunRelaunchReconciler.reconcile(first.threads, now: now)

        XCTAssertEqual(first.interruptedThreadIDs, [thread.id])
        XCTAssertTrue(second.changedThreadIDs.isEmpty)
        XCTAssertTrue(second.interruptedThreadIDs.isEmpty)
        XCTAssertEqual(second.threads, first.threads)
    }
}
