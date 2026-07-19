import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp
@testable import quill_code_desktop

/// Controller-level coverage for the failed-run Retry notification action — specifically the two
/// ordering hazards the #1369 review round confirmed: (1) `selectThread`'s follow-up recovery drain
/// must not steal the send slot and swallow the retry when the failed thread has queued follow-ups
/// and is not selected; (2) a stale tap must be a pure no-op that does not even navigate (so it can
/// never destroy a live confidential session as a side effect).
@MainActor
final class QuillCodeDesktopRunRetryTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("desktop-run-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeController(workspaceRoot: URL) throws -> QuillCodeDesktopController {
        let stateRoot = try makeTempDirectory().appendingPathComponent("state", isDirectory: true)
        let paths = QuillCodePaths(home: stateRoot)
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory)
        return QuillCodeDesktopController(
            bootstrap: bootstrap,
            browserPageFetcher: URLSessionBrowserPageFetcher(),
            browserLiveDOMCapturer: nil,
            // The platform-default notifier requires a real app bundle (UNUserNotificationCenter
            // crashes in a bare test process) — the known bundle-crash gotcha.
            automationNotifier: RunRetryTestNoopNotifier(),
            workspaceRoot: workspaceRoot
        )
    }

    private func waitForIdleSend(
        _ controller: QuillCodeDesktopController,
        threadID: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<300 {
            if !controller.tasks.isSendRunning(threadID: threadID),
               !controller.model.isAgentRunActive(for: threadID) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("send never went idle", file: file, line: line)
    }

    func testRetryRunsTheContinuationBeforeQueuedFollowUpsOnAnUnselectedThread() async throws {
        let root = try makeTempDirectory()
        let controller = try makeController(workspaceRoot: root)
        let model = controller.model

        // Seed a failed thread WITH queued follow-ups, then deselect it — the review scenario.
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        let failedThreadID = try XCTUnwrap(model.selectedThread?.id)
        let failedIndex = try XCTUnwrap(model.root.threads.firstIndex { $0.id == failedThreadID })
        model.root.threads[failedIndex].events.append(.init(
            kind: .notice,
            summary: "\(WorkspaceRunFailureNoticePlanner.noticePrefix): transient blip"
        ))
        model.root.threads[failedIndex].followUpQueue.append(.init(text: "queued follow-up"))

        model.newChat()
        XCTAssertNotEqual(model.selectedThread?.id, failedThreadID)

        controller.retryFailedRunFromNotification(threadID: failedThreadID)
        try await waitForIdleSend(controller, threadID: failedThreadID)

        let thread = try XCTUnwrap(model.root.threads.first { $0.id == failedThreadID })
        let userMessages = thread.messages.filter { $0.role == .user }.map(\.content)
        let retryIndex = userMessages.firstIndex(of: QuillCodeWorkspaceModel.failedRunRetryPrompt)
        let followUpIndex = userMessages.firstIndex(of: "queued follow-up")
        XCTAssertNotNil(retryIndex, "the continuation prompt must run — not be swallowed by the recovery drain")
        XCTAssertNotNil(followUpIndex, "the queued follow-up must still drain")
        if let retryIndex, let followUpIndex {
            XCTAssertLessThan(retryIndex, followUpIndex, "continuation runs BEFORE the queued follow-ups")
        }
        XCTAssertTrue(thread.followUpQueue.isEmpty, "the retry wave drains the queue")
    }

    func testStaleRetryTapDoesNotNavigateOrTouchAnything() async throws {
        let root = try makeTempDirectory()
        let controller = try makeController(workspaceRoot: root)
        let model = controller.model

        // A healthy (non-failed) thread, then deselect it.
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)
        let healthyThreadID = try XCTUnwrap(model.selectedThread?.id)
        model.newChat()
        let selectedAfterNewChat = model.selectedThread?.id

        controller.retryFailedRunFromNotification(threadID: healthyThreadID)

        XCTAssertEqual(
            model.selectedThread?.id,
            selectedAfterNewChat,
            "a stale tap must not navigate (selectThread has destructive side effects)"
        )
        let thread = try XCTUnwrap(model.root.threads.first { $0.id == healthyThreadID })
        XCTAssertFalse(
            thread.messages.contains { $0.content == QuillCodeWorkspaceModel.failedRunRetryPrompt },
            "a stale tap must not send anything"
        )
    }
}

private struct RunRetryTestNoopNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
