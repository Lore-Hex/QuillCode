import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceModelRunRetryTests: XCTestCase {
    private func failureNotice() -> ThreadEvent {
        .init(kind: .notice, summary: "\(WorkspaceRunFailureNoticePlanner.noticePrefix): something transient")
    }

    // MARK: - lastRunFailed detection

    func testLastRunFailedRequiresATrailingFailureNotice() {
        var thread = ChatThread(mode: .auto)
        XCTAssertFalse(QuillCodeWorkspaceModel.lastRunFailed(in: thread), "empty thread has no failed run")

        thread.events.append(failureNotice())
        XCTAssertTrue(QuillCodeWorkspaceModel.lastRunFailed(in: thread))

        // Trailing non-failure notices (run-integrity verdict, token usage) do not mask the failure.
        thread.events.append(.init(kind: .notice, summary: "run-integrity-report"))
        XCTAssertTrue(QuillCodeWorkspaceModel.lastRunFailed(in: thread))

        // Any substantive event after the failure means the thread moved on — the failure is stale.
        thread.events.append(.init(kind: .message, summary: "user typed something new"))
        XCTAssertFalse(QuillCodeWorkspaceModel.lastRunFailed(in: thread))
    }

    func testLastRunFailedIsFalseForASuccessfulRun() {
        var thread = ChatThread(mode: .auto)
        thread.events.append(.init(kind: .message, summary: "hi"))
        thread.events.append(.init(kind: .toolCompleted, summary: "host.shell.run completed"))
        XCTAssertFalse(QuillCodeWorkspaceModel.lastRunFailed(in: thread))
    }

    // MARK: - Gate

    func testCanRetryFailedRunGates() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        XCTAssertFalse(model.canRetryFailedRun(threadID: UUID()), "unknown thread must refuse")

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        let threadID = try XCTUnwrap(model.selectedThread?.id)
        XCTAssertFalse(model.canRetryFailedRun(threadID: threadID), "a successful run is not retryable")

        let index = try XCTUnwrap(model.root.threads.firstIndex { $0.id == threadID })
        model.root.threads[index].events.append(failureNotice())
        XCTAssertTrue(model.canRetryFailedRun(threadID: threadID))
    }

    // MARK: - Retry turn

    func testRetryFailedRunSendsTheContinuationTurnThroughTheSharedEngine() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        let threadID = try XCTUnwrap(model.selectedThread?.id)
        let index = try XCTUnwrap(model.root.threads.firstIndex { $0.id == threadID })
        model.root.threads[index].events.append(failureNotice())
        let messageCountBefore = model.root.threads[index].messages.count

        await model.retryFailedRun(threadID: threadID, workspaceRoot: root)

        let thread = try XCTUnwrap(model.root.threads.first { $0.id == threadID })
        let userMessages = thread.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(
            userMessages.last,
            QuillCodeWorkspaceModel.failedRunRetryPrompt,
            "the retry must append the continuation prompt as the next user turn"
        )
        XCTAssertGreaterThan(
            thread.messages.count,
            messageCountBefore,
            "the retry turn must actually run (mock runtime replies)"
        )
        XCTAssertFalse(
            model.canRetryFailedRun(threadID: threadID),
            "after a retried run the failure is no longer the thread's trailing state"
        )
    }

    func testRetryFailedRunIsANoOpWithoutAFailedLastRun() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        let threadID = try XCTUnwrap(model.selectedThread?.id)
        let before = try XCTUnwrap(model.root.threads.first { $0.id == threadID })

        await model.retryFailedRun(threadID: threadID, workspaceRoot: root)

        let after = try XCTUnwrap(model.root.threads.first { $0.id == threadID })
        XCTAssertEqual(after.messages.count, before.messages.count, "a stale retry tap must not touch the thread")
        XCTAssertEqual(after.events.count, before.events.count)
    }
}
