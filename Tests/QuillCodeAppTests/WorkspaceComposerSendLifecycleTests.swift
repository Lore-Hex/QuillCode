import XCTest
@testable import QuillCodeApp

final class WorkspaceComposerSendLifecycleTests: XCTestCase {
    func testStartedClearsDraftAndMarksSendRunning() {
        let plan = WorkspaceComposerSendLifecycle.started(from: ComposerState(
            draft: "run tests",
            isSending: false,
            placeholder: "Message"
        ))

        XCTAssertEqual(plan.composer.draft, "")
        XCTAssertTrue(plan.composer.isSending)
        XCTAssertEqual(plan.composer.placeholder, "Message")
        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.running)
    }

    func testCompletedPreservesDraftAndClearsSendingState() {
        let plan = WorkspaceComposerSendLifecycle.completed(from: ComposerState(
            draft: "",
            isSending: true
        ))

        XCTAssertEqual(plan.composer.draft, "")
        XCTAssertFalse(plan.composer.isSending)
        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.idle)
    }

    func testCancelledClearsSendingStateWithoutShowingError() {
        let plan = WorkspaceComposerSendLifecycle.cancelled(from: ComposerState(
            draft: "",
            isSending: true
        ))

        XCTAssertFalse(plan.composer.isSending)
        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testFailedClearsSendingStateAndReportsDescribedError() {
        let plan = WorkspaceComposerSendLifecycle.failed(SampleError.nope, from: ComposerState(
            draft: "",
            isSending: true
        ))

        XCTAssertFalse(plan.composer.isSending)
        XCTAssertEqual(plan.lastError, "nope")
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.failed)
    }
}

private enum SampleError: Error, CustomStringConvertible {
    case nope

    var description: String {
        "nope"
    }
}
