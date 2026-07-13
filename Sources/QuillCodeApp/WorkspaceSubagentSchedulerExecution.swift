import Foundation
import QuillCodeCore

private enum WorkspaceSubagentWorkerOutcome: Sendable, Hashable {
    case finished(WorkspaceSubagentWorkerResult)
    case cancelled
    case failed(String)
}

extension WorkspaceSubagentScheduler {
    func runPrepared(
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        jobs initialJobs: [WorkspaceSubagentJob],
        items initialItems: [SubagentProgressItem],
        pendingApprovals initialPendingApprovals: [String: SubagentPendingApproval],
        createdAt: Date,
        effectiveMaxDepth: Int,
        effectiveMaxTotalJobs: Int,
        progress: ProgressSink?,
        state: StateSink?,
        spawn: Spawner?
    ) async -> WorkspaceSubagentRunResult {
        var jobs = initialJobs
        var items = initialItems
        var pendingApprovals = initialPendingApprovals
        var dependencies = Self.resolvedDependencies(for: jobs)
        var usedNames = Set(jobs.map { $0.name.lowercased() })

        await publishCheckpoint(
            request: request,
            runID: runID,
            jobs: jobs,
            items: items,
            pendingApprovals: pendingApprovals,
            maxDepth: effectiveMaxDepth,
            maxTotalJobs: effectiveMaxTotalJobs,
            createdAt: createdAt,
            progress: progress,
            state: state
        )

        // Run dependency waves until every worker has finished or the remaining graph is paused
        // behind an approval/interruption. A real dependency cycle is broken deterministically, but
        // a paused dependency is never mistaken for a cycle and bypassed.
        while items.contains(where: { !Self.isTerminal($0.status) }) {
            let skipped = Self.cancelWorkersWithFailedDependencies(
                dependencies: dependencies,
                items: &items
            )
            if skipped {
                await publishCheckpoint(
                    request: request,
                    runID: runID,
                    jobs: jobs,
                    items: items,
                    pendingApprovals: pendingApprovals,
                    maxDepth: effectiveMaxDepth,
                    maxTotalJobs: effectiveMaxTotalJobs,
                    createdAt: createdAt,
                    progress: progress,
                    state: state
                )
            }

            let pending = items.indices.filter { !Self.isTerminal(items[$0].status) }
            if pending.isEmpty { break }
            let paused = Set(pending.filter { index in
                Self.dependsOnPausedWorker(index, dependencies: dependencies, items: items)
            })
            var runnable = pending.filter { index in
                !paused.contains(index)
                    && dependencies[index].allSatisfy { items[$0].status == .completed }
            }
            if runnable.isEmpty {
                let cycleCandidates = pending.filter { !paused.contains($0) }
                guard !cycleCandidates.isEmpty else {
                    Self.markBlockedWorkers(pending, dependencies: dependencies, items: &items)
                    await publishCheckpoint(
                        request: request,
                        runID: runID,
                        jobs: jobs,
                        items: items,
                        pendingApprovals: pendingApprovals,
                        maxDepth: effectiveMaxDepth,
                        maxTotalJobs: effectiveMaxTotalJobs,
                        createdAt: createdAt,
                        progress: progress,
                        state: state
                    )
                    break
                }
                // The remaining unpaused workers form a genuine cycle or reference an unavailable
                // dependency. Treat only those workers as roots; paused branches stay blocked.
                runnable = cycleCandidates
            }

            Self.markRunnableWorkers(runnable, pending: pending, dependencies: dependencies, items: &items)
            await publishCheckpoint(
                request: request,
                runID: runID,
                jobs: jobs,
                items: items,
                pendingApprovals: pendingApprovals,
                maxDepth: effectiveMaxDepth,
                maxTotalJobs: effectiveMaxTotalJobs,
                createdAt: createdAt,
                progress: progress,
                state: state
            )

            let spawned = await runWave(
                runnable: runnable,
                request: request,
                runID: runID,
                jobs: jobs,
                dependencies: dependencies,
                items: &items,
                pendingApprovals: &pendingApprovals,
                maxDepth: effectiveMaxDepth,
                maxTotalJobs: effectiveMaxTotalJobs,
                createdAt: createdAt,
                progress: progress,
                state: state,
                spawn: spawn
            )

            if enqueue(
                spawned,
                runID: runID,
                objective: request.objective,
                maxDepth: effectiveMaxDepth,
                maxTotalJobs: effectiveMaxTotalJobs,
                jobs: &jobs,
                dependencies: &dependencies,
                items: &items,
                usedNames: &usedNames
            ) {
                await publishCheckpoint(
                    request: request,
                    runID: runID,
                    jobs: jobs,
                    items: items,
                    pendingApprovals: pendingApprovals,
                    maxDepth: effectiveMaxDepth,
                    maxTotalJobs: effectiveMaxTotalJobs,
                    createdAt: createdAt,
                    progress: progress,
                    state: state
                )
            }
        }

        let update = SubagentProgressUpdate(objective: request.objective, subagents: items)
        let summary = Self.finalSummary(objective: request.objective, items: items)
        let record = Self.runRecord(
            request: request,
            runID: runID,
            jobs: jobs,
            items: items,
            pendingApprovals: pendingApprovals,
            maxDepth: effectiveMaxDepth,
            maxTotalJobs: effectiveMaxTotalJobs,
            createdAt: createdAt
        )
        await state?(record)
        return WorkspaceSubagentRunResult(update: update, summary: summary, record: record)
    }

    private func runWave(
        runnable: [Int],
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        jobs: [WorkspaceSubagentJob],
        dependencies: [[Int]],
        items: inout [SubagentProgressItem],
        pendingApprovals: inout [String: SubagentPendingApproval],
        maxDepth: Int,
        maxTotalJobs: Int,
        createdAt: Date,
        progress: ProgressSink?,
        state: StateSink?,
        spawn: Spawner?
    ) async -> [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] {
        let waveLimit = max(1, request.maxConcurrentWorkers ?? runnable.count)
        var spawned: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] = []
        await withTaskGroup(of: (Int, WorkspaceSubagentWorkerOutcome).self) { group in
            var queued = runnable[...]

            func startNextWorker() {
                guard let index = queued.first else { return }
                queued = queued.dropFirst()
                var job = jobs[index]
                job.priorResults = dependencies[index].compactMap { dependencyIndex in
                    guard items[dependencyIndex].status == .completed,
                          let summary = items[dependencyIndex].summary
                    else { return nil }
                    return WorkspaceSubagentPriorResult(
                        name: items[dependencyIndex].name,
                        summary: summary
                    )
                }
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let result = try await worker(job)
                        try Task.checkCancellation()
                        return (index, .finished(result))
                    } catch is CancellationError {
                        return (index, .cancelled)
                    } catch {
                        return (index, .failed(error.localizedDescription))
                    }
                }
            }

            for _ in 0..<min(waveLimit, runnable.count) {
                startNextWorker()
            }

            while let (index, outcome) = await group.next() {
                startNextWorker()
                switch outcome {
                case .finished(let result):
                    items[index].status = result.status
                    items[index].summary = Self.boundedSummary(result.summary)
                    items[index].transcript = result.transcript
                    pendingApprovals[jobs[index].id] = result.pendingApproval
                    if result.status == .completed, let spawn {
                        for child in await spawn(jobs[index], result.summary) {
                            spawned.append((parentIndex: index, request: child))
                        }
                    }
                case .cancelled:
                    items[index].status = .cancelled
                    items[index].summary = "Cancelled"
                case .failed(let summary):
                    items[index].status = .failed
                    items[index].summary = Self.boundedSummary(summary)
                }
                await publishCheckpoint(
                    request: request,
                    runID: runID,
                    jobs: jobs,
                    items: items,
                    pendingApprovals: pendingApprovals,
                    maxDepth: maxDepth,
                    maxTotalJobs: maxTotalJobs,
                    createdAt: createdAt,
                    progress: progress,
                    state: state
                )
            }
        }
        return spawned
    }

    private func publishCheckpoint(
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        jobs: [WorkspaceSubagentJob],
        items: [SubagentProgressItem],
        pendingApprovals: [String: SubagentPendingApproval],
        maxDepth: Int,
        maxTotalJobs: Int,
        createdAt: Date,
        progress: ProgressSink?,
        state: StateSink?
    ) async {
        await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))
        await state?(Self.runRecord(
            request: request,
            runID: runID,
            jobs: jobs,
            items: items,
            pendingApprovals: pendingApprovals,
            maxDepth: maxDepth,
            maxTotalJobs: maxTotalJobs,
            createdAt: createdAt
        ))
    }

    private func enqueue(
        _ spawned: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)],
        runID: UUID,
        objective: String,
        maxDepth: Int,
        maxTotalJobs: Int,
        jobs: inout [WorkspaceSubagentJob],
        dependencies: inout [[Int]],
        items: inout [SubagentProgressItem],
        usedNames: inout Set<String>
    ) -> Bool {
        var enqueued = false
        for (parentIndex, child) in spawned {
            let parent = jobs[parentIndex]
            guard parent.depth + 1 <= maxDepth else { continue }
            guard jobs.count < maxTotalJobs else { break }
            let childName = Self.uniqueChildName(parent: parent, child: child, used: &usedNames)
            let childJob = WorkspaceSubagentJob(
                runID: runID,
                name: childName,
                role: child.role,
                objective: objective,
                dependsOn: [parent.name],
                dependencyIDs: [parent.id],
                groupPath: parent.groupPath + [parent.name],
                depth: parent.depth + 1
            )
            jobs.append(childJob)
            items.append(SubagentProgressItem(
                workerID: childJob.id,
                name: childName,
                role: child.role,
                status: .queued,
                groupPath: childJob.groupPath
            ))
            dependencies.append([parentIndex])
            enqueued = true
        }
        return enqueued
    }
}
