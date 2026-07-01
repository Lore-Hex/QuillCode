import XCTest
import QuillCodeAgent
@testable import QuillCodeApp

final class WorkspaceModelSelfHealingNoticeTests: XCTestCase {
    @MainActor
    func testSelfHealAppearsAsANoticeInTheRunThread() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        // Simulate the retry decorator having self-healed a rate limit during the run.
        let channel = RetryEventChannel()
        channel.record(attempt: 1, kind: .rateLimited)
        model.retryEventChannel = channel

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let notices = (model.selectedThread?.events ?? []).filter { $0.kind == .notice }
        XCTAssertTrue(
            notices.contains { $0.summary.contains("Self-healing: retrying after a rate limit") },
            "expected a self-healing notice; got \(notices.map(\.summary))"
        )
        XCTAssertTrue(channel.drain().isEmpty, "the channel should have been drained")
    }

    @MainActor
    func testSelfHealNotMisattributedToADifferentThread() async throws {
        // A run's self-heal must land on the RUN's thread, not whatever thread is selected now. Draining
        // with a threadID that is not the selected thread must NOT append (and must clear the channel so
        // the event never bleeds onto a later run).
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        let channel = RetryEventChannel()
        channel.record(attempt: 1, kind: .transport)
        model.retryEventChannel = channel

        // Drain as if the finished run had targeted some OTHER (no-longer-selected) thread.
        model.drainSelfHealingNotices(expectedThreadID: UUID())

        let notices = (model.selectedThread?.events ?? []).filter { $0.kind == .notice }
        XCTAssertFalse(notices.contains { $0.summary.contains("Self-healing") }, "must not append to the wrong thread")
        XCTAssertTrue(channel.drain().isEmpty, "the channel is still cleared, so the event never bleeds into a later run")
    }

    @MainActor
    func testNoChannelIsANoOp() async throws {
        // Mock runtime has no retry channel; a run produces no self-healing notice.
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let notices = (model.selectedThread?.events ?? []).filter { $0.kind == .notice }
        XCTAssertFalse(notices.contains { $0.summary.contains("Self-healing") })
    }
}
