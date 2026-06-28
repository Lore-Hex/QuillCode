import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSubagentSchedulerTests: XCTestCase {
    func testSchedulerRunsWorkersConcurrentlyAndPublishesProgress() async throws {
        let probe = ConcurrencyProbe()
        let scheduler = WorkspaceSubagentScheduler { job in
            await probe.started(job.name)
            try await Task.sleep(nanoseconds: 20_000_000)
            await probe.finished(job.name)
            return "checked \(job.role)"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "validate release",
            workers: [
                .init(name: "Explorer", role: "inspect code"),
                .init(name: "Verifier", role: "run tests")
            ]
        )
        let progress = ProgressRecorder()

        let result = await scheduler.run(request: request) { update in
            await progress.record(update)
        }

        let maxRunning = await probe.maximumRunningCount()
        XCTAssertEqual(maxRunning, 2)
        XCTAssertEqual(result.update.subagents.map(\.status), [.completed, .completed])
        XCTAssertEqual(result.update.subagents.map(\.summary), ["checked inspect code", "checked run tests"])
        XCTAssertTrue(result.summary.contains("Subagents completed 2 workers"))
        let updates = await progress.updates
        XCTAssertEqual(updates.first?.subagents.map(\.status), [.queued, .queued])
        XCTAssertEqual(updates.dropFirst().first?.subagents.map(\.status), [.running, .running])
        XCTAssertEqual(updates.last?.subagents.map(\.status), [.completed, .completed])
    }

    func testSchedulerMarksFailedWorkersWithoutDroppingSuccessfulResults() async throws {
        enum WorkerFailure: LocalizedError {
            case failed
            var errorDescription: String? { "worker exploded" }
        }
        let scheduler = WorkspaceSubagentScheduler { job in
            if job.name == "Broken" { throw WorkerFailure.failed }
            return "ok"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "validate release",
            workers: [
                .init(name: "Healthy", role: "inspect code"),
                .init(name: "Broken", role: "run tests")
            ]
        )

        let result = await scheduler.run(request: request)

        XCTAssertEqual(result.update.subagents.map(\.status), [.completed, .failed])
        XCTAssertEqual(result.update.subagents[0].summary, "ok")
        XCTAssertEqual(result.update.subagents[1].summary, "worker exploded")
        XCTAssertTrue(result.summary.contains("1 completed and 1 failed"))
    }
}

private actor ConcurrencyProbe {
    private var runningNames: Set<String> = []
    private var maxRunning = 0

    func started(_ name: String) {
        runningNames.insert(name)
        maxRunning = max(maxRunning, runningNames.count)
    }

    func finished(_ name: String) {
        runningNames.remove(name)
    }

    func maximumRunningCount() -> Int {
        maxRunning
    }
}

private actor ProgressRecorder {
    private(set) var updates: [SubagentProgressUpdate] = []

    func record(_ update: SubagentProgressUpdate) {
        updates.append(update)
    }
}
