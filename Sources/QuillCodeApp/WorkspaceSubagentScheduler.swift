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
    var groupPath: [String]
    var priorResults: [WorkspaceSubagentPriorResult]
    /// Delegation depth: top-level workers are 0; a child spawned by a worker is its parent's
    /// depth + 1. The scheduler refuses to spawn past `maxDepth`, which guarantees termination.
    var depth: Int

    init(
        name: String,
        role: String,
        objective: String = "",
        dependsOn: [String] = [],
        groupPath: [String] = [],
        priorResults: [WorkspaceSubagentPriorResult] = [],
        depth: Int = 0
    ) {
        self.name = name
        self.role = role
        self.objective = objective
        self.dependsOn = dependsOn
        self.groupPath = groupPath
        self.priorResults = priorResults
        self.depth = depth
    }
}

struct WorkspaceSubagentRunResult: Sendable, Hashable {
    var update: SubagentProgressUpdate
    var summary: String
}

struct WorkspaceSubagentWorkerResult: Sendable, Hashable {
    var summary: String
    var transcript: [SubagentTranscriptEntry]

    init(summary: String, transcript: [SubagentTranscriptEntry] = []) {
        self.summary = summary
        self.transcript = transcript
    }
}

private enum WorkspaceSubagentWorkerOutcome: Sendable, Hashable {
    case completed(WorkspaceSubagentWorkerResult)
    case cancelled
    case failed(String)
}

struct WorkspaceSubagentScheduler {
    typealias Worker = @Sendable (WorkspaceSubagentJob) async throws -> WorkspaceSubagentWorkerResult
    typealias SummaryWorker = @Sendable (WorkspaceSubagentJob) async throws -> String
    /// Called after a worker completes with its job and result summary; returns child workers to
    /// delegate to. Returning `[]` (or passing no spawner) keeps the flat, fixed-graph behavior.
    typealias Spawner = @Sendable (WorkspaceSubagentJob, String) async -> [WorkspaceSubagentWorkerRequest]
    typealias ProgressSink = @Sendable (SubagentProgressUpdate) async -> Void

    /// Recursive delegation can spawn workers up to this depth value (top-level workers are depth 0),
    /// i.e. the default of 3 allows up to four levels: 0 → 1 → 2 → 3. Combined with `maxTotalJobs` it
    /// bounds an otherwise unbounded recursion so a run always terminates.
    static let defaultMaxDepth = 3
    /// Hard ceiling on how many workers a single run may ever schedule (top-level + spawned). A
    /// backstop against a spawner that keeps delegating within the depth bound.
    static let defaultMaxTotalJobs = 64

    private let worker: Worker
    private let maxDepth: Int
    private let maxTotalJobs: Int

    init(
        maxDepth: Int = Self.defaultMaxDepth,
        maxTotalJobs: Int = Self.defaultMaxTotalJobs,
        worker: @escaping Worker = Self.defaultWorker
    ) {
        self.worker = worker
        self.maxDepth = max(0, maxDepth)
        self.maxTotalJobs = max(1, maxTotalJobs)
    }

    init(
        maxDepth: Int = Self.defaultMaxDepth,
        maxTotalJobs: Int = Self.defaultMaxTotalJobs,
        summaryWorker: @escaping SummaryWorker
    ) {
        self.init(maxDepth: maxDepth, maxTotalJobs: maxTotalJobs) { job in
            WorkspaceSubagentWorkerResult(summary: try await summaryWorker(job))
        }
    }

    func run(
        request: WorkspaceSubagentRunRequest,
        progress: ProgressSink? = nil,
        spawn: Spawner? = nil
    ) async -> WorkspaceSubagentRunResult {
        var jobs = request.workers.map {
            WorkspaceSubagentJob(
                name: $0.name,
                role: $0.role,
                objective: request.objective,
                dependsOn: $0.dependsOn,
                groupPath: $0.groupPath
            )
        }
        var items = jobs.map {
            SubagentProgressItem(name: $0.name, role: $0.role, status: .queued, groupPath: $0.groupPath)
        }
        await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))

        // Indices into `jobs`/`items` align with `dependencies`. Recursive spawning appends to all
        // three in lockstep (children resolve to no dependencies — their parent has already
        // completed), so existing indices stay valid.
        var dependencies = Self.resolvedDependencies(for: jobs)
        var usedNames = Set(jobs.map { $0.name.lowercased() })

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

            // Cap how many ready workers run at once. `nil` (the default) keeps the original
            // behavior of fanning every runnable worker out together; a bound seeds that many
            // tasks and starts one more each time a worker finishes.
            let waveLimit = max(1, request.maxConcurrentWorkers ?? runnable.count)
            // Children requested by workers that completed this wave; applied after the wave so we
            // never mutate `jobs`/`items` while the task group is still reading them.
            var spawnedThisWave: [(parentIndex: Int, request: WorkspaceSubagentWorkerRequest)] = []
            await withTaskGroup(of: (Int, WorkspaceSubagentWorkerOutcome).self) { group in
                var queued = runnable[...]

                func startNextWorker() {
                    guard let index = queued.first else { return }
                    queued = queued.dropFirst()
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
                            let result = try await worker(job)
                            try Task.checkCancellation()
                            return (index, .completed(result))
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
                    // A worker finished, freeing a slot — dispatch the next queued worker immediately,
                    // before any (possibly slow, model-driven) spawn handling, so a bounded wave keeps
                    // its concurrency saturated.
                    startNextWorker()
                    switch outcome {
                    case .completed(let result):
                        items[index].status = .completed
                        items[index].summary = Self.boundedSummary(result.summary)
                        items[index].transcript = result.transcript
                        if let spawn {
                            for child in await spawn(jobs[index], result.summary) {
                                spawnedThisWave.append((parentIndex: index, request: child))
                            }
                        }
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

            // Enqueue children requested this wave, bounded by depth and the total-job ceiling so the
            // outer loop always drains to a terminal state. A child depends on its (already-completed)
            // parent, so it runs in the next pass and inherits the parent's result summary through the
            // same priorResults plumbing dependent workers use — delegated work keeps parent context.
            if !spawnedThisWave.isEmpty {
                var enqueuedAny = false
                for (parentIndex, child) in spawnedThisWave {
                    let parentDepth = jobs[parentIndex].depth
                    guard parentDepth + 1 <= maxDepth else { continue }
                    guard jobs.count < maxTotalJobs else { break }
                    let parentName = jobs[parentIndex].name
                    let childName = Self.uniqueChildName(parent: jobs[parentIndex], child: child, used: &usedNames)
                    let childJob = WorkspaceSubagentJob(
                        name: childName,
                        role: child.role,
                        objective: request.objective,
                        dependsOn: [parentName],
                        groupPath: jobs[parentIndex].groupPath + [parentName],
                        depth: parentDepth + 1
                    )
                    jobs.append(childJob)
                    var item = SubagentProgressItem(name: childName, role: child.role, status: .queued)
                    item.groupPath = childJob.groupPath
                    items.append(item)
                    // Resolve the child's single dependency directly to the parent index rather than
                    // through resolvedDependencies(by name): the parent index is known and exact, which
                    // sidesteps the case-insensitive, first-name-wins name resolution that could
                    // otherwise mis-resolve dependsOn:[parentName] when two workers share a name.
                    dependencies.append([parentIndex])
                    enqueuedAny = true
                }
                if enqueuedAny {
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

    /// Namespaces a spawned child under its parent (mirroring the nested `groupPath`) and guarantees
    /// the name — which is the job `id` and the key for dependency/progress resolution — is unique
    /// within the run, so two parents spawning a "Compile" child never collide.
    private static func uniqueChildName(
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

    private static func defaultWorker(_ job: WorkspaceSubagentJob) async throws -> WorkspaceSubagentWorkerResult {
        await Task.yield()
        return WorkspaceSubagentWorkerResult(summary: "Completed \(job.role)")
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
