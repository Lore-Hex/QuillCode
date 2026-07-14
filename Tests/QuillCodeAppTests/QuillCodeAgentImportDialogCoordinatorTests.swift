import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class QuillCodeAgentImportDialogCoordinatorTests: XCTestCase {
    func testBeginLoadsDefaultSelectionAndProjectToggleRemovesScopedItems() async {
        let preview = makePreview()
        let coordinator = QuillCodeAgentImportDialogCoordinator()

        coordinator.begin(using: QuillCodeAgentImportActions(
            discover: { preview },
            perform: { _ in AgentImportOutcome(source: .claudeCode) }
        ))
        await waitUntil { coordinator.phase == .review }

        XCTAssertEqual(coordinator.selectedCandidateIDs, preview.defaultCandidateIDs)
        XCTAssertEqual(coordinator.selectedProjectPaths, ["/project"])
        XCTAssertTrue(coordinator.canImport)

        coordinator.toggleProject(preview.projects[0])

        XCTAssertEqual(coordinator.selectedProjectPaths, [])
        XCTAssertEqual(coordinator.selectedCandidateIDs, ["global"])
        XCTAssertFalse(coordinator.canImport)
    }

    func testPerformUsesCurrentSelectionAndShowsOutcome() async {
        let preview = makePreview()
        let recorder = AgentImportSelectionRecorder()
        let expected = AgentImportOutcome(
            source: .claudeCode,
            imported: [AgentImportCount(kind: .instructions, count: 1)]
        )
        let coordinator = QuillCodeAgentImportDialogCoordinator()
        let actions = QuillCodeAgentImportActions(
            discover: { preview },
            perform: { selection in
                recorder.selection = selection
                return expected
            }
        )
        coordinator.begin(using: actions)
        await waitUntil { coordinator.phase == .review }

        coordinator.toggleCandidate(preview.candidates[1])
        coordinator.perform(using: actions)
        await waitUntil { coordinator.phase == .result }

        XCTAssertEqual(recorder.selection?.candidateIDs, ["global"])
        XCTAssertEqual(recorder.selection?.projectPaths, ["/project"])
        XCTAssertEqual(coordinator.outcome, expected)
    }

    func testDismissIgnoresLateDiscoveryResult() async {
        let gate = AgentImportAsyncGate()
        let coordinator = QuillCodeAgentImportDialogCoordinator()
        coordinator.begin(using: QuillCodeAgentImportActions(
            discover: {
                await gate.wait()
                return self.makePreview()
            },
            perform: { _ in AgentImportOutcome(source: .claudeCode) }
        ))
        XCTAssertEqual(coordinator.phase, .loading)

        coordinator.dismiss()
        await gate.open()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertNil(coordinator.preview)
        XCTAssertFalse(coordinator.isPresented)
    }

    private func makePreview() -> AgentImportPreview {
        AgentImportPreview(
            source: .claudeCode,
            projects: [AgentImportProject(name: "Project", path: "/project", isAlreadyRegistered: false)],
            candidates: [
                AgentImportCandidate(
                    id: "global",
                    kind: .instructions,
                    title: "Global instructions",
                    detail: "All selected projects"
                ),
                AgentImportCandidate(
                    id: "scoped",
                    kind: .chats,
                    title: "Recent chat",
                    detail: "Two messages",
                    projectPath: "/project"
                )
            ]
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class AgentImportSelectionRecorder {
    var selection: AgentImportSelection?
}

private actor AgentImportAsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
