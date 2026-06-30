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

    func testSchedulerCapsConcurrencyAtTheRequestedLimit() async throws {
        let probe = ConcurrencyProbe()
        let scheduler = WorkspaceSubagentScheduler { job in
            await probe.started(job.name)
            try await Task.sleep(nanoseconds: 20_000_000)
            await probe.finished(job.name)
            return "checked \(job.role)"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "audit",
            workers: [
                .init(name: "A", role: "one"),
                .init(name: "B", role: "two"),
                .init(name: "C", role: "three"),
                .init(name: "D", role: "four")
            ],
            maxConcurrentWorkers: 2
        )

        let result = await scheduler.run(request: request)

        let maxRunning = await probe.maximumRunningCount()
        XCTAssertEqual(maxRunning, 2, "No more than the requested number of workers should run at once.")
        XCTAssertEqual(result.update.subagents.map(\.status), [.completed, .completed, .completed, .completed])
        XCTAssertTrue(result.summary.contains("Subagents completed 4 workers"))
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
        XCTAssertTrue(result.summary.contains("1 completed, 0 cancelled, and 1 failed"))
    }

    func testSchedulerMarksCancelledWorkersWithoutTreatingThemAsFailures() async throws {
        let scheduler = WorkspaceSubagentScheduler { job in
            if job.name == "Stopped" { throw CancellationError() }
            return "finished normally"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "fan out review",
            workers: [
                .init(name: "Completed", role: "inspect code"),
                .init(name: "Stopped", role: "run long task")
            ]
        )
        let progress = ProgressRecorder()

        let result = await scheduler.run(request: request) { update in
            await progress.record(update)
        }

        XCTAssertEqual(result.update.subagents.map(\.status), [.completed, .cancelled])
        XCTAssertEqual(result.update.subagents[0].summary, "finished normally")
        XCTAssertEqual(result.update.subagents[1].summary, "Cancelled")
        XCTAssertTrue(result.summary.contains("1 completed, 1 cancelled, and 0 failed"))
        let updates = await progress.updates
        XCTAssertEqual(updates.last?.subagents.map(\.status), [.completed, .cancelled])
    }
    func testSchedulerRunsDependentWorkerOnlyAfterItsDependencyCompletes() async throws {
        let order = OrderRecorder()
        let scheduler = WorkspaceSubagentScheduler { job in
            await order.start(job.name)
            try await Task.sleep(nanoseconds: 10_000_000)
            await order.finish(job.name)
            return "did \(job.role)"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "ship release",
            workers: [
                .init(name: "Builder", role: "compile app"),
                .init(name: "Verifier", role: "run tests", dependsOn: ["Builder"])
            ]
        )
        let progress = ProgressRecorder()

        let result = await scheduler.run(request: request) { update in
            await progress.record(update)
        }

        XCTAssertEqual(result.update.subagents.map(\.status), [.completed, .completed])
        // Verifier must not start until Builder has finished.
        let starts = await order.startOrder
        let finishes = await order.finishOrder
        XCTAssertEqual(starts, ["Builder", "Verifier"])
        XCTAssertEqual(finishes.first, "Builder")
        // The dependent worker surfaces as blocked while it waits.
        let updates = await progress.updates
        let sawBlockedVerifier = updates.contains { update in
            update.subagents.contains { $0.name == "Verifier" && $0.status == .blocked }
        }
        XCTAssertTrue(sawBlockedVerifier, "Dependent worker should publish blocked progress while waiting.")
    }

    func testSchedulerSkipsDependentWhenItsDependencyFails() async throws {
        enum WorkerFailure: LocalizedError {
            case failed
            var errorDescription: String? { "builder exploded" }
        }
        let scheduler = WorkspaceSubagentScheduler { job in
            if job.name == "Builder" { throw WorkerFailure.failed }
            return "did \(job.role)"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "ship release",
            workers: [
                .init(name: "Builder", role: "compile app"),
                .init(name: "Verifier", role: "run tests", dependsOn: ["Builder"])
            ]
        )

        let result = await scheduler.run(request: request)

        XCTAssertEqual(result.update.subagents.map(\.status), [.failed, .cancelled])
        XCTAssertEqual(result.update.subagents[1].summary, "Skipped: dependency Builder did not complete")
        XCTAssertTrue(result.summary.contains("0 completed, 1 cancelled, and 1 failed"))
    }

    func testSchedulerHandsCompletedDependencyResultsToDependentWorker() async throws {
        let capture = JobCapture()
        let scheduler = WorkspaceSubagentScheduler { job in
            await capture.record(job)
            return "compiled the app cleanly"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "ship release",
            workers: [
                .init(name: "Builder", role: "compile app"),
                .init(name: "Verifier", role: "run tests", dependsOn: ["Builder"])
            ]
        )

        _ = await scheduler.run(request: request)

        let verifierJob = await capture.job(named: "Verifier")
        XCTAssertEqual(verifierJob?.priorResults, [
            WorkspaceSubagentPriorResult(name: "Builder", summary: "compiled the app cleanly")
        ])
        let builderJob = await capture.job(named: "Builder")
        XCTAssertEqual(builderJob?.priorResults, [], "Root jobs should not receive prior results.")
    }

    func testSchedulerPreservesNestedGroupPathInJobsAndProgress() async throws {
        let capture = JobCapture()
        let scheduler = WorkspaceSubagentScheduler { job in
            await capture.record(job)
            return "checked \(job.name)"
        }
        let request = WorkspaceSubagentRunRequest(
            objective: "ship nested plan",
            workers: [
                .init(name: "Frontend/UX", role: "inspect flow", groupPath: ["Frontend"]),
                .init(
                    name: "Frontend/Tests",
                    role: "run UI checks",
                    dependsOn: ["Frontend/UX"],
                    groupPath: ["Frontend"]
                )
            ]
        )

        let result = await scheduler.run(request: request)

        let verifierJob = await capture.job(named: "Frontend/Tests")
        XCTAssertEqual(verifierJob?.groupPath, ["Frontend"])
        XCTAssertEqual(verifierJob?.priorResults, [
            WorkspaceSubagentPriorResult(name: "Frontend/UX", summary: "checked Frontend/UX")
        ])
        XCTAssertEqual(result.update.subagents.map(\.name), ["Frontend/UX", "Frontend/Tests"])
        XCTAssertEqual(result.update.subagents.map(\.groupPath), [["Frontend"], ["Frontend"]])
    }

    func testSchedulerBreaksDependencyCyclesInsteadOfDeadlocking() async throws {
        let scheduler = WorkspaceSubagentScheduler { job in "did \(job.role)" }
        let request = WorkspaceSubagentRunRequest(
            objective: "cyclic",
            workers: [
                .init(name: "A", role: "first", dependsOn: ["B"]),
                .init(name: "B", role: "second", dependsOn: ["A"])
            ]
        )

        let result = await scheduler.run(request: request)

        // A cycle must still terminate with both workers completing.
        XCTAssertEqual(result.update.subagents.map(\.status), [.completed, .completed])
    }

    // MARK: - Recursive delegation

    func testWorkerCanSpawnAChildThatRunsToCompletion() async {
        let capture = JobCapture()
        let scheduler = WorkspaceSubagentScheduler { job in
            await capture.record(job)
            return "did \(job.role)"
        }
        let request = WorkspaceSubagentRunRequest(objective: "build", workers: [.init(name: "Builder", role: "build")])

        // Only the top-level Builder delegates; the child does not delegate further.
        let result = await scheduler.run(request: request, spawn: { job, _ in
            job.name == "Builder" ? [WorkspaceSubagentWorkerRequest(name: "Compile", role: "compile")] : []
        })

        XCTAssertEqual(result.update.subagents.count, 2)
        let child = result.update.subagents.first { $0.name == "Builder/Compile" }
        XCTAssertEqual(child?.status, .completed, "the spawned child should run to completion")
        XCTAssertEqual(child?.groupPath, ["Builder"], "the child should be nested under its parent")
        XCTAssertEqual(child?.summary, "did compile")
        let ranChild = await capture.job(named: "Builder/Compile")
        XCTAssertEqual(ranChild?.depth, 1, "the child runs at the parent's depth + 1")
        // Delegated work inherits the parent's result through the priorResults plumbing.
        XCTAssertEqual(ranChild?.priorResults, [WorkspaceSubagentPriorResult(name: "Builder", summary: "did build")])
    }

    func testTwoSameNamedChildrenFromOneParentAreDeduplicated() async {
        let scheduler = WorkspaceSubagentScheduler { _ in "ok" }
        let request = WorkspaceSubagentRunRequest(objective: "dup", workers: [.init(name: "Root", role: "r")])

        // One parent delegates two children that requested the identical name.
        let result = await scheduler.run(request: request, spawn: { job, _ in
            job.name == "Root"
                ? [
                    WorkspaceSubagentWorkerRequest(name: "Check", role: "c1"),
                    WorkspaceSubagentWorkerRequest(name: "Check", role: "c2")
                ]
                : []
        })

        let names = result.update.subagents.map(\.name)
        XCTAssertTrue(names.contains("Root/Check"))
        XCTAssertTrue(names.contains("Root/Check#2"), "a colliding child name is de-duplicated with a #suffix")
        XCTAssertEqual(Set(names).count, names.count, "every job id stays unique")
        XCTAssertEqual(result.update.subagents.count, 3)
        XCTAssertTrue(result.update.subagents.allSatisfy { $0.status == SubagentStatus.completed })
    }

    func testRecursiveSpawnsStopAtMaxDepth() async {
        let capture = JobCapture()
        let scheduler = WorkspaceSubagentScheduler(maxDepth: 2) { job in
            await capture.record(job)
            return "ok"
        }
        let request = WorkspaceSubagentRunRequest(objective: "deep", workers: [.init(name: "Root", role: "r")])

        // Every completed worker delegates one more child; only maxDepth bounds the recursion.
        let result = await scheduler.run(request: request, spawn: { _, _ in
            [WorkspaceSubagentWorkerRequest(name: "child", role: "c")]
        })

        let depths = await capture.depths()
        XCTAssertEqual(depths.max(), 2, "recursion must stop at maxDepth (no depth-3 worker)")
        XCTAssertEqual(result.update.subagents.count, 3, "depths 0, 1, 2 -> three workers")
        XCTAssertTrue(result.update.subagents.allSatisfy { $0.status == SubagentStatus.completed })
    }

    func testRecursiveSpawnsStopAtTheTotalJobCap() async {
        let scheduler = WorkspaceSubagentScheduler(maxDepth: 10, maxTotalJobs: 5) { _ in "ok" }
        let request = WorkspaceSubagentRunRequest(objective: "explode", workers: [.init(name: "Root", role: "r")])

        // Two children per worker would explode without the ceiling; the run must still terminate.
        let result = await scheduler.run(request: request, spawn: { _, _ in
            [
                WorkspaceSubagentWorkerRequest(name: "a", role: "a"),
                WorkspaceSubagentWorkerRequest(name: "b", role: "b")
            ]
        })

        XCTAssertLessThanOrEqual(result.update.subagents.count, 5, "the total-job ceiling must bound the run")
        XCTAssertGreaterThan(result.update.subagents.count, 1, "some children should have spawned")
        XCTAssertTrue(result.update.subagents.allSatisfy { $0.status == SubagentStatus.completed })
    }

    func testSpawnerReturningNoChildrenLeavesTheGraphFlat() async {
        let scheduler = WorkspaceSubagentScheduler { _ in "ok" }
        let request = WorkspaceSubagentRunRequest(objective: "flat", workers: [.init(name: "Solo", role: "s")])

        let result = await scheduler.run(request: request, spawn: { _, _ in [] })

        XCTAssertEqual(result.update.subagents.map(\.name), ["Solo"])
    }

    func testTwoParentsSpawningTheSameChildNameGetDistinctNestedJobs() async {
        let scheduler = WorkspaceSubagentScheduler { _ in "ok" }
        let request = WorkspaceSubagentRunRequest(
            objective: "fan",
            workers: [.init(name: "P1", role: "a"), .init(name: "P2", role: "b")]
        )

        // Both top-level parents delegate a child with the SAME requested name.
        let result = await scheduler.run(request: request, spawn: { job, _ in
            job.depth == 0 ? [WorkspaceSubagentWorkerRequest(name: "Check", role: "check")] : []
        })

        let names = Set(result.update.subagents.map(\.name))
        XCTAssertTrue(names.contains("P1/Check"), "child names are namespaced under the parent")
        XCTAssertTrue(names.contains("P2/Check"))
        XCTAssertEqual(result.update.subagents.count, 4, "the two same-named children stay distinct jobs")
    }
}

private actor OrderRecorder {
    private(set) var startOrder: [String] = []
    private(set) var finishOrder: [String] = []

    func start(_ name: String) { startOrder.append(name) }
    func finish(_ name: String) { finishOrder.append(name) }
}

private actor JobCapture {
    private var jobs: [WorkspaceSubagentJob] = []

    func record(_ job: WorkspaceSubagentJob) { jobs.append(job) }
    func job(named name: String) -> WorkspaceSubagentJob? { jobs.first { $0.name == name } }
    func depths() -> [Int] { jobs.map(\.depth) }
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
