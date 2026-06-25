import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentSendStartPlannerTests: XCTestCase {
    func testStartedPlanCarriesPromptThreadAndThreadID() {
        let thread = ChatThread(title: "Work")

        let plan = WorkspaceAgentSendStartPlanner.started(
            prompt: "Run tests",
            thread: thread,
            composer: ComposerState(draft: "Run tests", isSending: false)
        )

        XCTAssertEqual(plan.prompt, "Run tests")
        XCTAssertEqual(plan.thread.id, thread.id)
        XCTAssertEqual(plan.threadID, thread.id)
    }

    func testStartedPlanClearsDraftAndMarksComposerSending() {
        let plan = WorkspaceAgentSendStartPlanner.started(
            prompt: "Run tests",
            thread: ChatThread(title: "Work"),
            composer: ComposerState(draft: "Run tests", isSending: false)
        )

        XCTAssertEqual(plan.lifecycle.composer.draft, "")
        XCTAssertTrue(plan.lifecycle.composer.isSending)
        XCTAssertNil(plan.lifecycle.lastError)
        XCTAssertEqual(plan.lifecycle.agentStatus, TopBarAgentStatusLabel.running)
    }
}
