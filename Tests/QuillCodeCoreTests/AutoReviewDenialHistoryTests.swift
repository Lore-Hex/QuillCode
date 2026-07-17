import XCTest
@testable import QuillCodeCore

final class AutoReviewDenialHistoryTests: XCTestCase {
    func testHistoryReconstructsNewestTenDenialsAndConsumesExactRetry() throws {
        let root = URL(fileURLWithPath: "/tmp/quillcode-auto-review-history")
        var thread = ChatThread(messages: [.init(role: .user, content: "Run the requested actions")])
        var requestIDs: [String] = []

        for index in 0..<12 {
            let call = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"echo \#(index)"}"#)
            let request = request(call: call, thread: thread, root: root)
            requestIDs.append(request.id)
            thread.events.append(requestEvent(request, date: Date(timeIntervalSince1970: TimeInterval(index))))
            thread.events.append(decisionEvent(requestID: request.id, outcome: .denied))
        }

        let retry = ApprovalRequest(
            toolCall: ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"echo 11"}"#),
            toolDefinition: nil,
            reason: "Exact retry",
            reviewAttempt: .denialOverride(requestID: requestIDs[11])
        )
        thread.events.append(requestEvent(retry, date: Date(timeIntervalSince1970: 20)))

        let records = AutoReviewDenialHistory.records(in: thread, workspaceRoot: root)

        XCTAssertEqual(records.count, 10)
        XCTAssertEqual(records.first?.id, requestIDs[11])
        XCTAssertEqual(records.first?.retryState, .consumed)
        XCTAssertEqual(records.last?.id, requestIDs[2])
    }

    func testHistoryMarksRedactedCallsUnavailableAndChangedTurnContext() throws {
        let root = URL(fileURLWithPath: "/tmp/quillcode-auto-review-context")
        var thread = ChatThread(messages: [.init(role: .user, content: "Run it")])
        let privateCall = ToolCall(
            name: "host.shell.run",
            argumentsJSON: #"{"cmd":"env","env":{"TOKEN":"secret"}}"#
        )
        let privateRequest = request(
            call: privateCall,
            presentedCall: privateCall.redactedForTranscript(),
            thread: thread,
            root: root
        )
        thread.events.append(requestEvent(privateRequest))
        thread.events.append(decisionEvent(requestID: privateRequest.id, outcome: .denied))

        XCTAssertEqual(
            AutoReviewDenialHistory.records(in: thread, workspaceRoot: root).first?.retryState,
            .unavailable
        )

        let safeCall = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"whoami"}"#)
        let safeRequest = request(call: safeCall, thread: thread, root: root)
        thread.events.append(requestEvent(safeRequest))
        thread.events.append(decisionEvent(requestID: safeRequest.id, outcome: .denied))
        thread.messages.append(.init(role: .user, content: "A different turn"))

        let changed = try XCTUnwrap(
            AutoReviewDenialHistory.records(in: thread, workspaceRoot: root)
                .first(where: { $0.id == safeRequest.id })
        )
        XCTAssertEqual(changed.retryState, .contextChanged)
    }

    func testLegacyApprovalEventsDecodeWithoutRetryMetadata() throws {
        let json = #"{"id":"legacy","scope":"tool","toolCall":{"id":"tool-1","name":"host.shell.run","argumentsJSON":"{}"},"reason":"legacy"}"#
        let request = try JSONHelpers.decode(ApprovalRequest.self, from: json)
        XCTAssertEqual(request.reviewAttempt, .initial)
        XCTAssertNil(request.actionIdentity)

        let decisionJSON = #"{"requestID":"legacy","verdict":"deny","rationale":"legacy"}"#
        let decision = try JSONHelpers.decode(ApprovalDecision.self, from: decisionJSON)
        XCTAssertEqual(decision.reviewOutcome, .denied)
    }

    private func request(
        call: ToolCall,
        presentedCall: ToolCall? = nil,
        thread: ChatThread,
        root: URL
    ) -> ApprovalRequest {
        let presentedCall = presentedCall ?? call
        return ApprovalRequest(
            toolCall: presentedCall,
            toolDefinition: nil,
            reason: "Denied",
            recommendedVerdict: .deny,
            actionIdentity: .make(
                executableCall: call,
                presentedCall: presentedCall,
                thread: thread,
                workspaceRoot: root
            )
        )
    }

    private func requestEvent(_ request: ApprovalRequest, date: Date = Date()) -> ThreadEvent {
        ThreadEvent(
            kind: .approvalRequested,
            createdAt: date,
            summary: "denied",
            payloadJSON: try? JSONHelpers.encodePretty(request)
        )
    }

    private func decisionEvent(
        requestID: String,
        outcome: ApprovalReviewOutcome
    ) -> ThreadEvent {
        let decision = ApprovalDecision(
            requestID: requestID,
            verdict: outcome == .approved ? .approve : .deny,
            rationale: "Reviewed",
            reviewOutcome: outcome
        )
        return ThreadEvent(
            kind: .approvalDecided,
            summary: outcome.displayLabel,
            payloadJSON: try? JSONHelpers.encodePretty(decision)
        )
    }
}
