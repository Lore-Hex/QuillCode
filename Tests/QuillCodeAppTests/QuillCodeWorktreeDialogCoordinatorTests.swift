import XCTest
@testable import QuillCodeApp

@MainActor
final class QuillCodeWorktreeDialogCoordinatorTests: XCTestCase {
    func testPresentOpenLoadsChoicesIntoOpenDraft() async {
        let coordinator = QuillCodeWorktreeDialogCoordinator()
        let choice = WorkspaceWorktreeChoice(
            path: "/repo/quill-feature",
            title: "quill-feature",
            detail: "feature/dialog"
        )

        coordinator.presentOpen {
            WorkspaceWorktreeChoiceLoad(choices: [choice])
        }

        await waitUntil("open choices loaded") {
            coordinator.openDraft.choiceLoad.hasLoaded
        }

        XCTAssertEqual(coordinator.sheet, .open)
        XCTAssertEqual(coordinator.openDraft.choiceLoad.choices, [choice])
        XCTAssertFalse(coordinator.openDraft.choiceLoad.isLoading)
    }

    func testSwitchingSheetsIgnoresStaleChoiceLoads() async {
        let coordinator = QuillCodeWorktreeDialogCoordinator()
        let gate = AsyncGate()
        let openStarted = expectation(description: "open load started")
        let openChoice = WorkspaceWorktreeChoice(path: "/repo/open", title: "open", detail: "open")
        let removeChoice = WorkspaceWorktreeChoice(path: "/repo/remove", title: "remove", detail: "remove")

        coordinator.presentOpen {
            openStarted.fulfill()
            await gate.wait()
            return WorkspaceWorktreeChoiceLoad(choices: [openChoice])
        }

        await fulfillment(of: [openStarted], timeout: 1)
        XCTAssertEqual(coordinator.sheet, .open)
        XCTAssertTrue(coordinator.openDraft.choiceLoad.isLoading)

        coordinator.presentRemove {
            WorkspaceWorktreeChoiceLoad(choices: [removeChoice])
        }

        await waitUntil("remove choices loaded") {
            coordinator.removeDraft.choiceLoad.hasLoaded
        }

        await gate.open()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(coordinator.sheet, .remove)
        XCTAssertEqual(coordinator.removeDraft.choiceLoad.choices, [removeChoice])
        XCTAssertFalse(coordinator.openDraft.choiceLoad.hasLoaded)
    }

    func testPrunePreviewRetryOnlyAppliesToVisiblePruneSheet() async {
        let coordinator = QuillCodeWorktreeDialogCoordinator()

        coordinator.retryPrunePreview {
            XCTFail("hidden prune retry should not load")
            return WorkspaceWorktreePrunePreview(records: ["Prunable worktree: /repo/stale"], output: "")
        }
        XCTAssertFalse(coordinator.pruneDraft.preview.isLoading)

        coordinator.presentPrune {
            WorkspaceWorktreePrunePreview(errorMessage: "not ready")
        }
        await waitUntil("initial prune preview loaded") {
            coordinator.pruneDraft.preview.hasLoaded
        }
        XCTAssertEqual(coordinator.pruneDraft.preview.errorMessage, "not ready")

        coordinator.retryPrunePreview {
            WorkspaceWorktreePrunePreview(
                records: ["Prunable worktree: /repo/stale"],
                output: "Prunable worktree: /repo/stale"
            )
        }
        await waitUntil("retried prune preview loaded") {
            coordinator.pruneDraft.preview.records == ["Prunable worktree: /repo/stale"]
        }

        XCTAssertEqual(coordinator.sheet, .prune)
        XCTAssertTrue(coordinator.pruneDraft.canPrune)
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)")
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
