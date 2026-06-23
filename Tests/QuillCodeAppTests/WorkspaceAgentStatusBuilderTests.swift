import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentStatusBuilderTests: XCTestCase {
    func testMapsToolLifecycleEventsToTopBarStatuses() {
        XCTAssertEqual(status(.toolQueued), "Queued")
        XCTAssertEqual(status(.toolRunning), "Running")
        XCTAssertEqual(status(.toolCompleted), "Finishing")
        XCTAssertEqual(status(.toolFailed), "Failed")
    }

    func testMapsApprovalAndStreamingEventsToTopBarStatuses() {
        XCTAssertEqual(status(.approvalRequested), "Review")
        XCTAssertEqual(
            status(.notice, summary: AgentRunner.streamingNotice),
            "Streaming"
        )
    }

    func testMapsConversationAndGenericNoticeEventsToRunning() {
        XCTAssertEqual(status(.message), "Running")
        XCTAssertEqual(status(.messageFeedback), "Running")
        XCTAssertEqual(status(.approvalDecided), "Running")
        XCTAssertEqual(status(.reviewComment), "Running")
        XCTAssertEqual(status(.notice, summary: "Saved memory"), "Running")
        XCTAssertEqual(WorkspaceAgentStatusBuilder.status(for: nil), "Running")
    }

    func testReadsLatestThreadEvent() {
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued"),
            ThreadEvent(kind: .toolFailed, summary: "failed")
        ])

        XCTAssertEqual(WorkspaceAgentStatusBuilder.status(for: thread), "Failed")
    }

    private func status(
        _ kind: ThreadEventKind,
        summary: String = "event"
    ) -> String {
        WorkspaceAgentStatusBuilder.status(for: ThreadEvent(kind: kind, summary: summary))
    }
}
