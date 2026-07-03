import XCTest
import QuillCodeCore
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
    func testCompletedRunRecordsAStableIntegrityVerdict() async throws {
        // #875: after a completed run, the integrity verdict is stamped onto the run's thread as a
        // persisted notice, so the Activity badge is stable across reloads.
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let thread = try XCTUnwrap(model.selectedThread)
        let recorded = try XCTUnwrap(
            RunIntegrityRecord.latest(in: thread),
            "a completed run should have a recorded integrity verdict"
        )
        // The benign whoami run makes no unbacked claims and leaves no failing test -> VERIFIED.
        XCTAssertEqual(recorded.verdict, .verified)
        // Exactly one integrity notice — repeated runs must not accumulate stale badges.
        XCTAssertEqual(thread.events.filter { RunIntegrityRecord.isRecord($0) }.count, 1)
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
