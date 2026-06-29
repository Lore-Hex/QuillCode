import Foundation
import QuillCodeCore

struct WorkspaceSubagentPriorResult: Sendable, Hashable {
    var name: String
    var summary: String

    init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}

struct WorkspaceSubagentJob: Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var role: String
    var objective: String
    var dependsOn: [String]
    var priorResults: [WorkspaceSubagentPriorResult]

    init(
        name: String,
        role: String,
        objective: String = "",
        dependsOn: [String] = [],
        priorResults: [WorkspaceSubagentPriorResult] = []
    ) {
        self.name = name
        self.role = role
        self.objective = objective
        self.dependsOn = dependsOn
        self.priorResults = priorResults
    }
}

struct WorkspaceSubagentRunResult: Sendable, Hashable {
    var update: SubagentProgressUpdate
    var summary: String
}

private enum WorkspaceSubagentWorkerOutcome: Sendable, Hashable {
    case completed(String)
    case cancelled
    case failed(String)
}

struct WorkspaceSubagentScheduler {
    typealias Worker = @Sendable (WorkspaceSubagentJob) async throws -> String
    typealias ProgressSink = @Sendable (SubagentProgressUpdate) async -> Void

    private let worker: Worker

    init(worker: @escaping Worker = Self.defaultWorker) {
        self.worker = worker
    }

    func run(
        request: WorkspaceSubagentRunRequest,
        progress: ProgressSink? = nil
    ) async -> WorkspaceSubagentRunResult {
        let jobs = request.workers.map {
            WorkspaceSubagentJob(
                name: $0.name,
                role: $0.role,
                objective: request.objective,
                dependsOn: $0.dependsOn
            )
        }
        var items = jobs.map {
            SubagentProgressItem(name: $0.name, role: $0.role, status: .queued)
        }
        await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))

        let dependencies = Self.resolvedDependencies(for: jobs)

        // Run jobs in dependency waves: each pass starts every job whose dependencies have all
        // completed, fans them out concurrently, then re-evaluates readiness. Jobs still waiting
        // surface as `.blocked`; jobs whose dependency failed or was cancelled are skipped. When no
        // job is runnable but some remain (a dependency cycle), the deadlock is broken by running
        // the remaining jobs as roots so the run always terminates.
        while items.contains(where: { !Self.isTerminal($0.status) }) {
            var skipped = false
            for index in items.indices where !Self.isTerminal(items[index].status) {
                if let blockedBy = dependencies[index].first(where: {
                    items[$0].status == .failed || items[$0].status == .cancelled
                }) {
                    items[index].status = .cancelled
                    items[index].summary = "Skipped: dependency \(items[blockedBy].name) did not complete"
                    skipped = true
                }
            }
            if skipped {
                await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))
            }

            let pending = items.indices.filter { !Self.isTerminal(items[$0].status) }
            if pending.isEmpty { break }
            var runnable = pending.filter { index in
                dependencies[index].allSatisfy { items[$0].status == .completed }
            }
            if runnable.isEmpty {
                // Dependency cycle or otherwise unsatisfiable graph: run remaining jobs as roots.
                runnable = pending
            }
            let runnableSet = Set(runnable)

            for index in pending {
                if runnableSet.contains(index) {
                    items[index].status = .running
                    items[index].summary = "Running \(items[index].role)"
                } else {
                    items[index].status = .blocked
                    let waiting = dependencies[index]
                        .filter { items[$0].status != .completed }
                        .map { items[$0].name }
                    items[index].summary = waiting.isEmpty
                        ? "Blocked"
                        : "Waiting on \(waiting.joined(separator: ", "))"
                }
            }
            await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))

            await withTaskGroup(of: (Int, WorkspaceSubagentWorkerOutcome).self) { group in
                for index in runnable {
                    var job = jobs[index]
                    // Hand the worker the concrete results of its completed prerequisites so a
                    // dependent model turn can build on what its dependencies actually produced.
                    job.priorResults = dependencies[index].compactMap { depIndex in
                        guard items[depIndex].status == .completed,
                              let summary = items[depIndex].summary else { return nil }
                        return WorkspaceSubagentPriorResult(name: items[depIndex].name, summary: summary)
                    }
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let summary = try await worker(job)
                            try Task.checkCancellation()
                            return (index, .completed(summary))
                        } catch is CancellationError {
                            return (index, .cancelled)
                        } catch {
                            return (index, .failed(error.localizedDescription))
                        }
                    }
                }

                for await (index, outcome) in group {
                    switch outcome {
                    case .completed(let summary):
                        items[index].status = .completed
                        items[index].summary = Self.boundedSummary(summary)
                    case .cancelled:
                        items[index].status = .cancelled
                        items[index].summary = "Cancelled"
                    case .failed(let summary):
                        items[index].status = .failed
                        items[index].summary = Self.boundedSummary(summary)
                    }
                    await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))
                }
            }
        }

        return WorkspaceSubagentRunResult(
            update: SubagentProgressUpdate(objective: request.objective, subagents: items),
            summary: Self.finalSummary(objective: request.objective, items: items)
        )
    }

    private static func isTerminal(_ status: SubagentStatus) -> Bool {
        status == .completed || status == .failed || status == .cancelled
    }

    /// Maps each job's declared dependency names to job indices, dropping unknown names, duplicates,
    /// and self-references. Name matching is case-insensitive and resolves to the first job with a
    /// given name so duplicated worker names stay deterministic.
    private static func resolvedDependencies(for jobs: [WorkspaceSubagentJob]) -> [[Int]] {
        var nameToIndex: [String: Int] = [:]
        for (index, job) in jobs.enumerated() {
            let key = job.name.lowercased()
            if nameToIndex[key] == nil { nameToIndex[key] = index }
        }
        return jobs.enumerated().map { index, job in
            var seen = Set<Int>()
            var resolved: [Int] = []
            for dependencyName in job.dependsOn {
                guard
                    let depIndex = nameToIndex[dependencyName.lowercased()],
                    depIndex != index,
                    !seen.contains(depIndex)
                else { continue }
                seen.insert(depIndex)
                resolved.append(depIndex)
            }
            return resolved
        }
    }

    private static func defaultWorker(_ job: WorkspaceSubagentJob) async throws -> String {
        await Task.yield()
        return "Completed \(job.role)"
    }

    private static func finalSummary(objective: String, items: [SubagentProgressItem]) -> String {
        let completed = items.filter { $0.status == .completed }.count
        let cancelled = items.filter { $0.status == .cancelled }.count
        let failed = items.filter { $0.status == .failed }.count
        let header = cancelled == 0 && failed == 0
            ? "Subagents completed \(completed) worker\(completed == 1 ? "" : "s") for: \(objective)"
            : "Subagents finished with \(completed) completed, \(cancelled) cancelled, and \(failed) failed worker\(items.count == 1 ? "" : "s") for: \(objective)"
        let rows = items.map { item in
            let summary = item.summary.map { " - \($0)" } ?? ""
            return "- \(item.name): \(item.status.label)\(summary)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func boundedSummary(_ text: String) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 220 else { return normalized }
        return String(normalized.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
