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
        let threadID = try XCTUnwrap(model.selectedThread?.id)
        AgentRunRetryScope.$threadID.withValue(threadID) {
            channel.record(attempt: 1, kind: .rateLimited)
        }
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
    func testBackgroundSelfHealIsAttributedToItsRunThread() async throws {
        // A run's self-heal must land on the RUN's thread, not whatever thread is selected now.
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        let runThreadID = model.newChat()
        let foregroundThreadID = model.newChat()

        let channel = RetryEventChannel()
        AgentRunRetryScope.$threadID.withValue(runThreadID) {
            channel.record(attempt: 1, kind: .transport)
        }
        model.retryEventChannel = channel

        model.drainSelfHealingNotices(expectedThreadID: runThreadID)

        let runThread = try XCTUnwrap(model.root.threads.first { $0.id == runThreadID })
        let foregroundThread = try XCTUnwrap(model.root.threads.first { $0.id == foregroundThreadID })
        XCTAssertTrue(runThread.events.contains { $0.summary.contains("Self-healing") })
        XCTAssertFalse(foregroundThread.events.contains { $0.summary.contains("Self-healing") })
        XCTAssertTrue(channel.drain().isEmpty)
    }

    @MainActor
    func testConcurrentRunRetryBucketsDrainIndependently() throws {
        let first = UUID()
        let second = UUID()
        let channel = RetryEventChannel()
        AgentRunRetryScope.$threadID.withValue(first) {
            channel.record(attempt: 1, kind: .rateLimited)
        }
        AgentRunRetryScope.$threadID.withValue(second) {
            channel.record(attempt: 2, kind: .transport)
        }

        XCTAssertEqual(channel.drain(threadID: second).map(\.kind), [.transport])
        XCTAssertEqual(channel.drain(threadID: first).map(\.kind), [.rateLimited])
        XCTAssertTrue(channel.drain().isEmpty)
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
