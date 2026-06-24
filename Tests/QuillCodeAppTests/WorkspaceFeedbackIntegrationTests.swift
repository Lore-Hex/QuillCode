import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceFeedbackIntegrationTests: XCTestCase {
    func testMessageFeedbackIsStoredAndSurfaced() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let assistantMessage = try XCTUnwrap(model.selectedThread?.messages.last)
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertTrue(model.setMessageFeedback(messageID: assistantMessage.id, value: .helpful))

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.events.last?.kind, .messageFeedback)
        XCTAssertEqual(WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces().last?.feedback, .helpful)
        XCTAssertEqual(WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems().last?.message?.feedback, .helpful)
        XCTAssertFalse(model.setMessageFeedback(messageID: thread.messages[0].id, value: .notHelpful))
    }
}
