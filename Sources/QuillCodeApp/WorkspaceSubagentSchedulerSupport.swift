import Foundation
import QuillCodeCore

extension WorkspaceSubagentScheduler {
    static func isTerminal(_ status: SubagentStatus) -> Bool {
        status == .completed
            || status == .failed
            || status == .cancelled
            || status == .awaitingApproval
            || status == .interrupted
    }

    static func resolveDependencyIDs(in jobs: inout [WorkspaceSubagentJob]) {
        var nameToID: [String: String] = [:]
        for job in jobs where nameToID[job.name.lowercased()] == nil {
            nameToID[job.name.lowercased()] = job.id
        }
        for index in jobs.indices where jobs[index].dependencyIDs.isEmpty {
            jobs[index].dependencyIDs = jobs[index].dependsOn.compactMap {
                nameToID[$0.lowercased()]
            }
        }
    }

    /// Maps each job's declared dependency IDs to job indices, dropping unknown IDs, duplicates,
    /// and self-references.
    static func resolvedDependencies(for jobs: [WorkspaceSubagentJob]) -> [[Int]] {
        let idToIndex = Dictionary(uniqueKeysWithValues: jobs.enumerated().map { ($0.element.id, $0.offset) })
        return jobs.enumerated().map { index, job in
            var seen = Set<Int>()
            return job.dependencyIDs.compactMap { dependencyID in
                guard let dependencyIndex = idToIndex[dependencyID],
                      dependencyIndex != index,
                      seen.insert(dependencyIndex).inserted
                else { return nil }
                return dependencyIndex
            }
        }
    }

    static func dependsOnPausedWorker(
        _ index: Int,
        dependencies: [[Int]],
        items: [SubagentProgressItem]
    ) -> Bool {
        var visited = Set<Int>()

        func visit(_ candidate: Int) -> Bool {
            guard visited.insert(candidate).inserted else { return false }
            for dependency in dependencies[candidate] {
                switch items[dependency].status {
                case .awaitingApproval, .interrupted:
                    return true
                case .completed, .failed, .cancelled:
                    continue
                case .queued, .running, .blocked:
                    if visit(dependency) { return true }
                }
            }
            return false
        }

        return visit(index)
    }

    @discardableResult
    static func cancelWorkersWithFailedDependencies(
        dependencies: [[Int]],
        items: inout [SubagentProgressItem]
    ) -> Bool {
        var changed = false
        for index in items.indices where !isTerminal(items[index].status) {
            guard let blockedBy = dependencies[index].first(where: {
                items[$0].status == .failed || items[$0].status == .cancelled
            }) else { continue }
            items[index].status = .cancelled
            items[index].summary = "Skipped: dependency \(items[blockedBy].name) did not complete"
            changed = true
        }
        return changed
    }

    static func markRunnableWorkers(
        _ runnable: [Int],
        pending: [Int],
        dependencies: [[Int]],
        items: inout [SubagentProgressItem]
    ) {
        let runnableSet = Set(runnable)
        for index in pending {
            if runnableSet.contains(index) {
                items[index].status = .running
                items[index].summary = "Running \(items[index].role)"
                continue
            }
            let waiting = dependencies[index]
                .filter { items[$0].status != .completed }
                .map { items[$0].name }
            items[index].status = .blocked
            items[index].summary = waiting.isEmpty
                ? "Blocked"
                : "Waiting on \(waiting.joined(separator: ", "))"
        }
    }

    static func markBlockedWorkers(
        _ indices: [Int],
        dependencies: [[Int]],
        items: inout [SubagentProgressItem]
    ) {
        for index in indices {
            let waiting = dependencies[index]
                .filter { items[$0].status != .completed }
                .map { items[$0].name }
            items[index].status = .blocked
            items[index].summary = waiting.isEmpty
                ? "Blocked"
                : "Waiting on \(waiting.joined(separator: ", "))"
        }
    }

    static func runRecord(
        request: WorkspaceSubagentRunRequest,
        runID: UUID,
        jobs: [WorkspaceSubagentJob],
        items: [SubagentProgressItem],
        pendingApprovals: [String: SubagentPendingApproval],
        maxDepth: Int,
        maxTotalJobs: Int,
        createdAt: Date
    ) -> SubagentRunRecord {
        let now = Date()
        let workers = zip(jobs, items).map { job, item in
            SubagentWorkerRecord(
                id: job.id,
                childThreadID: job.childThreadID,
                dependencyIDs: job.dependencyIDs,
                name: job.name,
                role: job.role,
                groupPath: job.groupPath,
                depth: job.depth,
                attempt: job.attempt,
                status: item.status,
                summary: item.summary,
                pendingApproval: pendingApprovals[job.id],
                updatedAt: now
            )
        }
        let finished = workers.allSatisfy { worker in
            worker.status == .completed || worker.status == .failed || worker.status == .cancelled
        }
        return SubagentRunRecord(
            id: runID,
            objective: request.objective,
            maxConcurrentWorkers: request.maxConcurrentWorkers,
            maxDepth: maxDepth,
            maxTotalJobs: maxTotalJobs,
            workers: workers,
            lastPublishedSummary: nil,
            createdAt: createdAt,
            updatedAt: now,
            finishedAt: finished ? now : nil
        )
    }

    static func uniqueChildName(
        parent: WorkspaceSubagentJob,
        child: WorkspaceSubagentWorkerRequest,
        used: inout Set<String>
    ) -> String {
        let base = "\(parent.name)/\(child.name)"
        var candidate = base
        var suffix = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(base)#\(suffix)"
            suffix += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }

    static func defaultWorker(_ job: WorkspaceSubagentJob) async throws -> String {
        await Task.yield()
        return "Completed \(job.role)"
    }

    static func finalSummary(objective: String, items: [SubagentProgressItem]) -> String {
        let completed = items.filter { $0.status == .completed }.count
        let cancelled = items.filter { $0.status == .cancelled }.count
        let failed = items.filter { $0.status == .failed }.count
        let approvals = items.filter { $0.status == .awaitingApproval }.count
        let interrupted = items.filter { $0.status == .interrupted }.count
        let blocked = items.filter { $0.status == .blocked }.count
        let paused = approvals + interrupted + blocked
        let header: String
        if paused > 0 {
            header = "Subagents paused with \(completed) completed, \(approvals) awaiting approval, "
                + "\(interrupted) interrupted, \(blocked) blocked, \(cancelled) cancelled, and \(failed) failed "
                + "worker\(items.count == 1 ? "" : "s") for: \(objective)"
        } else if cancelled == 0 && failed == 0 {
            header = "Subagents completed \(completed) worker\(completed == 1 ? "" : "s") for: \(objective)"
        } else {
            header = "Subagents finished with \(completed) completed, \(cancelled) cancelled, and "
                + "\(failed) failed worker\(items.count == 1 ? "" : "s") for: \(objective)"
        }
        let rows = items.map { item in
            let summary = item.summary.map { " - \($0)" } ?? ""
            return "- \(item.name): \(item.status.label)\(summary)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func boundedSummary(_ text: String) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 220 else { return normalized }
        return String(normalized.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
