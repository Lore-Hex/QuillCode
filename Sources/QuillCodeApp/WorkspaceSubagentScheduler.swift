import Foundation
import QuillCodeCore

struct WorkspaceSubagentJob: Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var role: String

    init(name: String, role: String) {
        self.name = name
        self.role = role
    }
}

struct WorkspaceSubagentRunResult: Sendable, Hashable {
    var update: SubagentProgressUpdate
    var summary: String
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
        let jobs = request.workers.map { WorkspaceSubagentJob(name: $0.name, role: $0.role) }
        var items = jobs.map {
            SubagentProgressItem(name: $0.name, role: $0.role, status: .queued)
        }
        await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))

        for index in items.indices {
            items[index].status = .running
            items[index].summary = "Running \(items[index].role)"
        }
        await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))

        await withTaskGroup(of: (Int, Result<String, any Error>).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await worker(job)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            for await (index, result) in group {
                switch result {
                case .success(let summary):
                    items[index].status = .completed
                    items[index].summary = Self.boundedSummary(summary)
                case .failure(let error):
                    items[index].status = .failed
                    items[index].summary = Self.boundedSummary(error.localizedDescription)
                }
                await progress?(SubagentProgressUpdate(objective: request.objective, subagents: items))
            }
        }

        return WorkspaceSubagentRunResult(
            update: SubagentProgressUpdate(objective: request.objective, subagents: items),
            summary: Self.finalSummary(objective: request.objective, items: items)
        )
    }

    private static func defaultWorker(_ job: WorkspaceSubagentJob) async throws -> String {
        await Task.yield()
        return "Completed \(job.role)"
    }

    private static func finalSummary(objective: String, items: [SubagentProgressItem]) -> String {
        let completed = items.filter { $0.status == .completed }.count
        let failed = items.filter { $0.status == .failed }.count
        let header = failed == 0
            ? "Subagents completed \(completed) worker\(completed == 1 ? "" : "s") for: \(objective)"
            : "Subagents finished with \(completed) completed and \(failed) failed worker\(failed == 1 ? "" : "s") for: \(objective)"
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
