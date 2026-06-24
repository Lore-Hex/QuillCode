import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceToolCardIntegrationTests: XCTestCase {
    func testToolCardsRepresentActionableApprovalReview() throws {
        let call = ToolCall(
            id: "approval-tool",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-request",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let event = ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify: needs target",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
        let thread = ChatThread(events: [event])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, ToolDefinition.shellRun.name)
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertTrue(cards[0].isExpanded)
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].reviewState, .ready)
        XCTAssertEqual(cards[0].inputJSON, ToolArguments.json(["cmd": "whoami"]))
        XCTAssertEqual(cards[0].actions.map(\.title), ["Run", "Edit", "Skip"])
    }

    func testToolCardApprovalActionRecordsDecisionAndRunsTool() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "approval-tool-run",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-run",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let thread = ChatThread(events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "review required",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didRun = model.runToolCardAction(ToolCardActionSurface(
            title: "Run",
            kind: .approve,
            requestID: "approval-run",
            style: .primary
        ), workspaceRoot: root)

        XCTAssertTrue(didRun)
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertTrue(events.contains { $0.kind == .approvalDecided })
        XCTAssertTrue(events.contains { $0.kind == .toolQueued })
        XCTAssertTrue(events.contains { $0.kind == .toolCompleted })
        let cards = model.currentToolCards
        XCTAssertTrue(cards.contains { $0.status == .done && $0.subtitle == "Approved · whoami" })
        XCTAssertTrue(cards.contains { $0.title == ToolDefinition.shellRun.name && $0.outputJSON?.contains("exitCode") == true })
    }

    func testToolCardEditActionPreloadsComposerWithoutDecidingOrRunningTool() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "approval-tool-edit",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "ls -la"])
        )
        let request = ApprovalRequest(
            id: "approval-edit",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let thread = ChatThread(events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "review required",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didEdit = model.runToolCardAction(ToolCardActionSurface(
            title: "Edit",
            kind: .edit,
            requestID: "approval-edit",
            style: .secondary
        ), workspaceRoot: root)

        XCTAssertTrue(didEdit)
        XCTAssertEqual(model.composer.draft, "Run ls -la")
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertFalse(events.contains { $0.kind == .approvalDecided })
        XCTAssertFalse(events.contains { $0.kind == .toolQueued })
        XCTAssertFalse(events.contains { $0.kind == .toolCompleted })
    }

    func testToolCardsRepresentStoppedActiveToolAsFailed() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "sleep 10"])
        )
        let callJSON = try JSONHelpers.encodePretty(call)
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(
                kind: .toolFailed,
                summary: "Stopped by user",
                payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
            ),
            ThreadEvent(kind: .notice, summary: "Stopped by user")
        ])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()
        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].status, .failed)
        XCTAssertEqual(cards[0].subtitle, "Failed · sleep 10")
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].outputJSON, #"{"ok":false,"error":"Stopped by user"}"#)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.status, .failed)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.density, .expanded)
    }
}
