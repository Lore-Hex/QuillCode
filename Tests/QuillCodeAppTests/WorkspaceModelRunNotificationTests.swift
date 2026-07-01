import XCTest
@testable import QuillCodeApp

final class WorkspaceModelRunNotificationTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        var value: AgentRunNotification?
    }

    @MainActor
    func testCompletedRunFiresComeBackNotification() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        let box = Box()
        model.onRunNotification = { box.value = $0 }

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        // A finished run pings the user (they may have walked away) with a summary of what happened.
        let note = try XCTUnwrap(box.value, "a finished run should fire a come-back notification")
        XCTAssertEqual(note.kind, .finished)
        XCTAssertFalse(note.body.isEmpty)
    }

    @MainActor
    func testNoHandlerIsANoOp() async throws {
        // Without a desktop handler (tests / CLI) the run completes normally and nothing is posted.
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertNil(model.onRunNotification)
    }
}
