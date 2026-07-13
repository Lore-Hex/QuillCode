import Foundation
import QuillCodeCore

struct WorkspaceSubagentScheduler: Sendable {
    typealias Worker = @Sendable (WorkspaceSubagentJob) async throws -> String
    typealias DetailedWorker = @Sendable (WorkspaceSubagentJob) async throws -> WorkspaceSubagentWorkerResult
    typealias Spawner = @Sendable (WorkspaceSubagentJob, String) async -> [WorkspaceSubagentWorkerRequest]
    typealias ProgressSink = @Sendable (SubagentProgressUpdate) async -> Void
    typealias StateSink = @Sendable (SubagentRunRecord) async -> Void

    /// Recursive delegation can spawn workers up to this depth value (top-level workers are depth 0).
    static let defaultMaxDepth = 3
    /// Hard ceiling for all top-level and recursively spawned workers in one run.
    static let defaultMaxTotalJobs = 64

    let worker: DetailedWorker
    let maxDepth: Int
    let maxTotalJobs: Int
    /// True only for the short-lived whole-session approval format. New production call sites use
    /// `detailedWorker:` and the compact durable manifest path.
    let usesLegacySessionAdapter: Bool

    init(
        maxDepth: Int = Self.defaultMaxDepth,
        maxTotalJobs: Int = Self.defaultMaxTotalJobs,
        worker: @escaping Worker = Self.defaultWorker
    ) {
        self.worker = { job in
            WorkspaceSubagentWorkerResult(summary: try await worker(job))
        }
        self.maxDepth = max(0, maxDepth)
        self.maxTotalJobs = max(1, maxTotalJobs)
        self.usesLegacySessionAdapter = false
    }

    init(
        maxDepth: Int = Self.defaultMaxDepth,
        maxTotalJobs: Int = Self.defaultMaxTotalJobs,
        legacyWorker: @escaping DetailedWorker
    ) {
        self.worker = legacyWorker
        self.maxDepth = max(0, maxDepth)
        self.maxTotalJobs = max(1, maxTotalJobs)
        self.usesLegacySessionAdapter = true
    }

    init(
        maxDepth: Int = Self.defaultMaxDepth,
        maxTotalJobs: Int = Self.defaultMaxTotalJobs,
        detailedWorker: @escaping DetailedWorker
    ) {
        self.worker = detailedWorker
        self.maxDepth = max(0, maxDepth)
        self.maxTotalJobs = max(1, maxTotalJobs)
        self.usesLegacySessionAdapter = false
    }

    func run(
        request: WorkspaceSubagentRunRequest,
        runID: UUID = UUID(),
        progress: ProgressSink? = nil,
        state: StateSink? = nil,
        spawn: Spawner? = nil
    ) async -> WorkspaceSubagentRunResult {
        if usesLegacySessionAdapter {
            return await runLegacy(
                request: request,
                runID: runID,
                progress: progress,
                spawn: spawn
            )
        }
        var jobs = request.workers.map {
            WorkspaceSubagentJob(
                runID: runID,
                name: $0.name,
                role: $0.role,
                objective: request.objective,
                dependsOn: $0.dependsOn,
                groupPath: $0.groupPath
            )
        }
        Self.resolveDependencyIDs(in: &jobs)
        let items = jobs.map {
            SubagentProgressItem(
                workerID: $0.id,
                name: $0.name,
                role: $0.role,
                status: .queued,
                groupPath: $0.groupPath
            )
        }
        return await runPrepared(
            request: request,
            runID: runID,
            jobs: jobs,
            items: items,
            pendingApprovals: [:],
            createdAt: Date(),
            effectiveMaxDepth: maxDepth,
            effectiveMaxTotalJobs: maxTotalJobs,
            progress: progress,
            state: state,
            spawn: spawn
        )
    }

    /// Continues a persisted graph after a held worker has been resolved. Stable worker and child
    /// transcript identities are preserved; work interrupted by a crash is never replayed implicitly.
    func resume(
        record: SubagentRunRecord,
        spawnFromWorkerIDs: Set<String> = [],
        progress: ProgressSink? = nil,
        state: StateSink? = nil,
        spawn: Spawner? = nil
    ) async -> WorkspaceSubagentRunResult {
        let nameByID = Dictionary(uniqueKeysWithValues: record.workers.map { ($0.id, $0.name) })
        var jobs = record.workers.map { worker in
            WorkspaceSubagentJob(
                runID: record.id,
                id: worker.id,
                childThreadID: worker.childThreadID,
                name: worker.name,
                role: worker.role,
                objective: record.objective,
                dependsOn: worker.dependencyIDs.compactMap { nameByID[$0] },
                dependencyIDs: worker.dependencyIDs,
                groupPath: worker.groupPath,
                attempt: worker.attempt,
                depth: worker.depth
            )
        }
        var items = record.workers.map { worker in
            SubagentProgressItem(
                workerID: worker.id,
                name: worker.name,
                role: worker.role,
                status: worker.status == .running ? .interrupted : worker.status,
                summary: worker.status == .running ? "Interrupted before completion" : worker.summary,
                groupPath: worker.groupPath
            )
        }
        let approvals = Dictionary(uniqueKeysWithValues: record.workers.compactMap { worker in
            worker.pendingApproval.map { (worker.id, $0) }
        })
        let request = WorkspaceSubagentRunRequest(
            objective: record.objective,
            workers: record.workers.map { worker in
                WorkspaceSubagentWorkerRequest(
                    name: worker.name,
                    role: worker.role,
                    dependsOn: worker.dependencyIDs.compactMap { nameByID[$0] },
                    groupPath: worker.groupPath
                )
            },
            maxConcurrentWorkers: record.maxConcurrentWorkers
        )

        if let spawn, !spawnFromWorkerIDs.isEmpty {
            appendSpawnedChildren(
                await spawnedChildren(
                    record: record,
                    jobs: jobs,
                    items: items,
                    workerIDs: spawnFromWorkerIDs,
                    spawn: spawn
                ),
                record: record,
                jobs: &jobs,
                items: &items
            )
        }

        return await runPrepared(
            request: request,
            runID: record.id,
            jobs: jobs,
            items: items,
            pendingApprovals: approvals,
            createdAt: record.createdAt,
            effectiveMaxDepth: max(0, record.maxDepth),
            effectiveMaxTotalJobs: max(1, record.maxTotalJobs),
            progress: progress,
            state: state,
            spawn: spawn
        )
    }

    private func spawnedChildren(
        record: SubagentRunRecord,
        jobs: [WorkspaceSubagentJob],
        items: [SubagentProgressItem],
        workerIDs: Set<String>,
        spawn: Spawner
    ) async -> [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] {
        var children: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] = []
        for parentIndex in jobs.indices where workerIDs.contains(jobs[parentIndex].id) {
            guard items[parentIndex].status == .completed,
                  let summary = items[parentIndex].summary,
                  jobs[parentIndex].depth + 1 <= max(0, record.maxDepth)
            else { continue }
            for child in await spawn(jobs[parentIndex], summary) {
                children.append((parentIndex: parentIndex, request: child))
            }
        }
        return children
    }

    private func appendSpawnedChildren(
        _ children: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)],
        record: SubagentRunRecord,
        jobs: inout [WorkspaceSubagentJob],
        items: inout [SubagentProgressItem]
    ) {
        var usedNames = Set(jobs.map { $0.name.lowercased() })
        for (parentIndex, child) in children {
            guard jobs.count < max(1, record.maxTotalJobs) else { break }
            let parent = jobs[parentIndex]
            let childName = Self.uniqueChildName(parent: parent, child: child, used: &usedNames)
            let childJob = WorkspaceSubagentJob(
                runID: record.id,
                name: childName,
                role: child.role,
                objective: record.objective,
                dependsOn: [parent.name],
                dependencyIDs: [parent.id],
                groupPath: parent.groupPath + [parent.name],
                depth: parent.depth + 1
            )
            jobs.append(childJob)
            items.append(SubagentProgressItem(
                workerID: childJob.id,
                name: childJob.name,
                role: childJob.role,
                status: .queued,
                groupPath: childJob.groupPath
            ))
        }
    }
}
