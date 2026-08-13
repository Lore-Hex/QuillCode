import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentProgressPersistencePolicyTests: XCTestCase {
    func testPersistsToolAndApprovalBoundaries() {
        for kind in [
            ThreadEventKind.toolQueued,
            .toolRunning,
            .toolCompleted,
            .toolFailed,
            .approvalRequested,
            .approvalDecided
        ] {
            XCTAssertTrue(WorkspaceAgentProgressPersistencePolicy.shouldPersist(
                previousLastEvent: .init(kind: .message, summary: "Prompt"),
                currentLastEvent: .init(kind: kind, summary: "Boundary")
            ), kind.rawValue)
        }
    }

    func testPersistsOnlyFirstContinuousProgressSnapshot() {
        XCTAssertTrue(WorkspaceAgentProgressPersistencePolicy.shouldPersist(
            previousLastEvent: .init(kind: .toolRunning, summary: "Running"),
            currentLastEvent: .init(kind: .toolProgress, summary: "First output")
        ))
        XCTAssertFalse(WorkspaceAgentProgressPersistencePolicy.shouldPersist(
            previousLastEvent: .init(kind: .toolProgress, summary: "First output"),
            currentLastEvent: .init(kind: .toolProgress, summary: "More output")
        ))
    }

    func testIgnoresPresentationOnlyAndUnchangedEvents() {
        let event = ThreadEvent(kind: .notice, summary: "Notice")
        XCTAssertFalse(WorkspaceAgentProgressPersistencePolicy.shouldPersist(
            previousLastEvent: event,
            currentLastEvent: event
        ))
        XCTAssertFalse(WorkspaceAgentProgressPersistencePolicy.shouldPersist(
            previousLastEvent: nil,
            currentLastEvent: .init(kind: .message, summary: "Streaming answer")
        ))
    }
}
