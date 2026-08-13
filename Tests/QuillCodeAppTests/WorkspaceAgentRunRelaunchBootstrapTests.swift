import Foundation
import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceAgentRunRelaunchBootstrapTests: XCTestCase {
    func testBootstrapPersistsInterruptedRecoveryExactlyOnceAndOffersSafeRetry() throws {
        let home = try makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let thread = ChatThread(
            messages: [.init(role: .user, content: "Run a long command")],
            events: [
                .init(kind: .message, summary: "Run a long command"),
                .init(kind: .toolQueued, summary: "host.shell.run queued"),
                .init(kind: .toolRunning, summary: "host.shell.run running")
            ],
            activeRunCheckpoint: ThreadRunCheckpoint(
                messageCountAtStart: 1,
                eventCountAtStart: 1
            )
        )
        try store.save(thread)

        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths, now: { now })
        let model = try bootstrap.makeModel(automaticStartupPolicy: .deferUntilRequested)
        let persisted = try store.load(thread.id)

        XCTAssertNil(persisted.activeRunCheckpoint)
        XCTAssertEqual(persisted.events.suffix(2).map(\.kind), [.toolFailed, .notice])
        XCTAssertFalse(model.isAgentRunActive(for: thread.id))
        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.lastError, WorkspaceAgentRunRelaunchReconciler.recoveryMessage)
        XCTAssertEqual(model.surface().runtimeIssue?.title, "Run interrupted")
        XCTAssertTrue(model.canRetryFailedRun(threadID: thread.id))

        XCTAssertTrue(model.prepareRetryLastUserTurn())
        XCTAssertEqual(model.composer.draft, QuillCodeWorkspaceModel.failedRunRetryPrompt)
        XCTAssertNil(model.lastError)

        let relaunched = try bootstrap.makeModel(automaticStartupPolicy: .deferUntilRequested)
        let persistedAgain = try store.load(thread.id)
        XCTAssertNil(relaunched.lastError)
        XCTAssertEqual(
            persistedAgain.events.filter {
                $0.summary == WorkspaceRunFailureNoticePlanner.interruptedRelaunchSummary
            }.count,
            1
        )
    }

    func testBootstrapRecoversInterruptedRunOutsideSelectedLaunchWorkingSet() throws {
        let home = try makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let interrupted = ChatThread(
            title: "Background task",
            messages: [.init(role: .user, content: "Run a long command")],
            events: [
                .init(kind: .message, summary: "Run a long command"),
                .init(kind: .toolRunning, summary: "host.shell.run running")
            ],
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now.addingTimeInterval(-100),
            activeRunCheckpoint: ThreadRunCheckpoint(
                messageCountAtStart: 1,
                eventCountAtStart: 1
            )
        )
        let selected = ChatThread(
            title: "Most recent chat",
            messages: [.init(role: .user, content: "This chat should open")],
            createdAt: now.addingTimeInterval(-10),
            updatedAt: now.addingTimeInterval(-10)
        )
        try [interrupted, selected].forEach(store.save)

        let model = try QuillCodeWorkspaceBootstrap(paths: paths, now: { now }).makeModel(
            automaticStartupPolicy: .deferUntilRequested
        )
        let persisted = try store.load(interrupted.id)

        XCTAssertEqual(model.selectedThread?.id, selected.id)
        XCTAssertNil(persisted.activeRunCheckpoint)
        XCTAssertEqual(persisted.events.suffix(2).map(\.kind), [.toolFailed, .notice])
        XCTAssertTrue(model.interruptedRunRecoveryThreadIDs.contains(interrupted.id))
    }
}
