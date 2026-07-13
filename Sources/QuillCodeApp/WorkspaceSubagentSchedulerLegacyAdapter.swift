import Foundation
import QuillCodeCore

private enum WorkspaceLegacySubagentOutcome: Sendable, Hashable {
    case completed(WorkspaceSubagentWorkerResult)
    case paused(WorkspaceSubagentApprovalPause)
    case cancelled
    case failed(String)
}

/// Reads and drains the whole-session format shipped immediately before compact subagent
/// manifests. It is intentionally isolated from the production scheduler: no new app run selects
/// this adapter, and recovered `.running` work becomes `.interrupted` instead of being replayed.
extension WorkspaceSubagentScheduler {
    func runLegacy(
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        progress: ProgressSink?,
        spawn: Spawner?
    ) async -> WorkspaceSubagentRunResult {
        let jobs = request.workers.map {
            WorkspaceSubagentJob(
                runID: runID,
                name: $0.name,
                role: $0.role,
                objective: request.objective,
                dependsOn: $0.dependsOn,
                groupPath: $0.groupPath
            )
        }
        let items = jobs.map {
            SubagentProgressItem(
                workerID: $0.id,
                name: $0.name,
                role: $0.role,
                status: .queued,
                groupPath: $0.groupPath
            )
        }
        let state = WorkspaceSubagentRunState(
            id: runID.uuidString,
            objective: request.objective,
            maxConcurrentWorkers: request.maxConcurrentWorkers,
            jobs: jobs,
            items: items
        )
        await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))
        return await run(state: state, progress: progress, spawn: spawn)
    }

    func run(
        state initialState: WorkspaceSubagentRunState,
        progress: ProgressSink? = nil,
        spawn: Spawner? = nil
    ) async -> WorkspaceSubagentRunResult {
        var state = initialState
        if !state.pausedWorkers.isEmpty {
            return legacyResult(state)
        }

        for index in state.items.indices where state.items[index].status == .running {
            state.items[index].status = .interrupted
            state.items[index].summary = "Interrupted before completion"
        }

        var dependencies = Self.legacyDependencies(for: state.jobs)
        var usedNames = Set(state.jobs.map { $0.name.lowercased() })

        while state.items.contains(where: { !Self.isTerminal($0.status) }) {
            if Self.cancelWorkersWithFailedDependencies(
                dependencies: dependencies,
                items: &state.items
            ) {
                await publishLegacyProgress(state, to: progress)
            }

            let pending = state.items.indices.filter { !Self.isTerminal(state.items[$0].status) }
            if pending.isEmpty { break }
            let frozen = Set(pending.filter { index in
                state.items[index].status == .awaitingApproval
                    || state.items[index].status == .interrupted
                    || Self.dependsOnPausedWorker(index, dependencies: dependencies, items: state.items)
            })
            var runnable = pending.filter { index in
                !frozen.contains(index)
                    && dependencies[index].allSatisfy { state.items[$0].status == .completed }
            }
            if runnable.isEmpty {
                let cycleCandidates = pending.filter { !frozen.contains($0) }
                guard !cycleCandidates.isEmpty else {
                    Self.markBlockedWorkers(pending, dependencies: dependencies, items: &state.items)
                    await publishLegacyProgress(state, to: progress)
                    break
                }
                runnable = cycleCandidates
            }

            Self.markRunnableWorkers(
                runnable,
                pending: pending,
                dependencies: dependencies,
                items: &state.items
            )
            await publishLegacyProgress(state, to: progress)

            let spawned = await runLegacyWave(
                runnable: runnable,
                state: &state,
                dependencies: dependencies,
                progress: progress,
                spawn: spawn
            )
            enqueueLegacyChildren(
                spawned,
                state: &state,
                dependencies: &dependencies,
                usedNames: &usedNames
            )
            if !spawned.isEmpty {
                await publishLegacyProgress(state, to: progress)
            }
            if !state.pausedWorkers.isEmpty { break }
        }

        return legacyResult(state)
    }

    private func runLegacyWave(
        runnable: [Int],
        state: inout WorkspaceSubagentRunState,
        dependencies: [[Int]],
        progress: ProgressSink?,
        spawn: Spawner?
    ) async -> [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] {
        let jobs = state.jobs
        let waveLimit = max(1, state.maxConcurrentWorkers ?? runnable.count)
        var outcomes: [(Int, WorkspaceLegacySubagentOutcome)] = []

        await withTaskGroup(of: (Int, WorkspaceLegacySubagentOutcome).self) { group in
            var queued = runnable[...]

            func startNext() {
                guard let index = queued.first else { return }
                queued = queued.dropFirst()
                var job = jobs[index]
                job.priorResults = dependencies[index].compactMap { dependencyIndex in
                    guard state.items[dependencyIndex].status == .completed,
                          let summary = state.items[dependencyIndex].summary
                    else { return nil }
                    return WorkspaceSubagentPriorResult(
                        name: state.items[dependencyIndex].name,
                        summary: summary
                    )
                }
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let result = try await worker(job)
                        try Task.checkCancellation()
                        return (index, .completed(result))
                    } catch is CancellationError {
                        return (index, .cancelled)
                    } catch let pause as WorkspaceSubagentApprovalPause {
                        return (index, .paused(pause))
                    } catch {
                        return (index, .failed(error.localizedDescription))
                    }
                }
            }

            for _ in 0..<min(waveLimit, runnable.count) { startNext() }
            while let outcome = await group.next() {
                outcomes.append(outcome)
                startNext()
            }
        }

        var spawned: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] = []
        for (index, outcome) in outcomes {
            switch outcome {
            case .completed(let result):
                state.items[index].status = result.status
                state.items[index].summary = Self.boundedSummary(result.summary)
                state.items[index].transcript = result.transcript
                if result.status == .completed, let spawn {
                    for child in await spawn(state.jobs[index], result.summary) {
                        spawned.append((parentIndex: index, request: child))
                    }
                }
            case .paused(let pause):
                let request = pause.pendingApproval.request
                state.items[index].status = .awaitingApproval
                state.items[index].summary = Self.boundedSummary(
                    "Approval needed for \(request.toolCall.name): \(request.reason)"
                )
                state.items[index].transcript = WorkspaceSubagentTranscriptBuilder.entries(from: pause.thread)
                state.items[index].approvalGate = SubagentApprovalGate(
                    runID: state.id,
                    requestID: request.id,
                    toolName: request.toolCall.name,
                    reason: request.reason
                )
                let key = WorkspaceSubagentPauseKey.unique(
                    workerName: state.jobs[index].name,
                    existing: state.pausedWorkers
                )
                state.pausedWorkers[key] = pause
            case .cancelled:
                state.items[index].status = .cancelled
                state.items[index].summary = "Cancelled"
            case .failed(let message):
                state.items[index].status = .failed
                state.items[index].summary = Self.boundedSummary(message)
            }
            await publishLegacyProgress(state, to: progress)
        }
        return spawned
    }

    private func enqueueLegacyChildren(
        _ spawned: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)],
        state: inout WorkspaceSubagentRunState,
        dependencies: inout [[Int]],
        usedNames: inout Set<String>
    ) {
        for (parentIndex, request) in spawned {
            guard state.jobs.count < maxTotalJobs else { break }
            let parent = state.jobs[parentIndex]
            guard parent.depth + 1 <= maxDepth else { continue }
            let name = Self.uniqueChildName(parent: parent, child: request, used: &usedNames)
            let child = WorkspaceSubagentJob(
                runID: UUID(uuidString: state.id) ?? parent.runID,
                name: name,
                role: request.role,
                objective: state.objective,
                dependsOn: [parent.name],
                dependencyIDs: [parent.id],
                groupPath: parent.groupPath + [parent.name],
                depth: parent.depth + 1
            )
            state.jobs.append(child)
            state.items.append(SubagentProgressItem(
                workerID: child.id,
                name: child.name,
                role: child.role,
                status: .queued,
                groupPath: child.groupPath
            ))
            dependencies.append([parentIndex])
        }
    }

    private func publishLegacyProgress(
        _ state: WorkspaceSubagentRunState,
        to progress: ProgressSink?
    ) async {
        await progress?(SubagentProgressUpdate(objective: state.objective, subagents: state.items))
    }

    private func legacyResult(_ state: WorkspaceSubagentRunState) -> WorkspaceSubagentRunResult {
        let update = SubagentProgressUpdate(objective: state.objective, subagents: state.items)
        return WorkspaceSubagentRunResult(
            update: update,
            summary: Self.finalSummary(objective: state.objective, items: state.items),
            record: Self.legacyRecord(state),
            legacyState: state
        )
    }

    private static func legacyDependencies(for jobs: [WorkspaceSubagentJob]) -> [[Int]] {
        var nameToIndex: [String: Int] = [:]
        for (index, job) in jobs.enumerated() where nameToIndex[job.name.lowercased()] == nil {
            nameToIndex[job.name.lowercased()] = index
        }
        return jobs.enumerated().map { index, job in
            var seen = Set<Int>()
            return job.dependsOn.compactMap { name in
                guard let dependency = nameToIndex[name.lowercased()],
                      dependency != index,
                      seen.insert(dependency).inserted
                else { return nil }
                return dependency
            }
        }
    }

    private static func legacyRecord(_ state: WorkspaceSubagentRunState) -> SubagentRunRecord {
        let nameToID = Dictionary(
            state.jobs.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let now = Date()
        let workers = zip(state.jobs, state.items).map { job, item in
            SubagentWorkerRecord(
                id: job.id,
                childThreadID: job.childThreadID,
                dependencyIDs: job.dependsOn.compactMap { nameToID[$0.lowercased()] },
                name: job.name,
                role: job.role,
                groupPath: job.groupPath,
                depth: job.depth,
                attempt: job.attempt,
                status: item.status,
                summary: item.summary,
                updatedAt: now
            )
        }
        let finished = state.pausedWorkers.isEmpty && workers.allSatisfy {
            $0.status == .completed || $0.status == .cancelled || $0.status == .failed
        }
        return SubagentRunRecord(
            id: UUID(uuidString: state.id) ?? UUID(),
            objective: state.objective,
            maxConcurrentWorkers: state.maxConcurrentWorkers,
            maxDepth: defaultMaxDepth,
            maxTotalJobs: defaultMaxTotalJobs,
            workers: workers,
            createdAt: now,
            updatedAt: now,
            finishedAt: finished ? now : nil
        )
    }
}
