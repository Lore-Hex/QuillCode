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

    func testStartedPlanCarriesImagesOntoUserMessageAndClearsComposerImages() throws {
        let attachment = try XCTUnwrap(ChatAttachment(
            displayName: "screen.png",
            format: .png,
            localURL: URL(fileURLWithPath: "/tmp/screen.png"),
            byteCount: 8
        ))
        let plan = WorkspaceAgentSendStartPlanner.started(
            prompt: "",
            attachments: [attachment],
            thread: ChatThread(),
            composer: ComposerState(attachments: [attachment])
        )

        XCTAssertEqual(plan.thread.messages.last?.attachments, [attachment])
        XCTAssertEqual(plan.thread.events.last?.summary, "Attached 1 image")
        XCTAssertEqual(plan.thread.title, "Image: screen.png")
        XCTAssertEqual(plan.lifecycle.composer.attachments, [])
    }
}
