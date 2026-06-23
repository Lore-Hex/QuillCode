import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentStatusBuilderTests: XCTestCase {
    func testMapsToolLifecycleEventsToTopBarStatuses() {
        XCTAssertEqual(status(.toolQueued), TopBarAgentStatusLabel.queued)
        XCTAssertEqual(status(.toolRunning), TopBarAgentStatusLabel.running)
        XCTAssertEqual(status(.toolCompleted), TopBarAgentStatusLabel.finishing)
        XCTAssertEqual(status(.toolFailed), TopBarAgentStatusLabel.failed)
    }

    func testMapsApprovalAndStreamingEventsToTopBarStatuses() {
        XCTAssertEqual(status(.approvalRequested), TopBarAgentStatusLabel.review)
        XCTAssertEqual(
            status(.notice, summary: AgentRunner.streamingNotice),
            TopBarAgentStatusLabel.streaming
        )
    }

    func testMapsConversationAndGenericNoticeEventsToRunning() {
        XCTAssertEqual(status(.message), TopBarAgentStatusLabel.running)
        XCTAssertEqual(status(.messageFeedback), TopBarAgentStatusLabel.running)
        XCTAssertEqual(status(.approvalDecided), TopBarAgentStatusLabel.running)
        XCTAssertEqual(status(.reviewComment), TopBarAgentStatusLabel.running)
        XCTAssertEqual(status(.notice, summary: "Saved memory"), TopBarAgentStatusLabel.running)
        XCTAssertEqual(WorkspaceAgentStatusBuilder.status(for: nil), TopBarAgentStatusLabel.running)
    }

    func testReadsLatestThreadEvent() {
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued"),
            ThreadEvent(kind: .toolFailed, summary: "failed")
        ])

        XCTAssertEqual(WorkspaceAgentStatusBuilder.status(for: thread), TopBarAgentStatusLabel.failed)
    }

    private func status(
        _ kind: ThreadEventKind,
        summary: String = "event"
    ) -> String {
        WorkspaceAgentStatusBuilder.status(for: ThreadEvent(kind: kind, summary: summary))
    }
}
