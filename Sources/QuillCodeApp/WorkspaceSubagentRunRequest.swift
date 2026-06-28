import Foundation

struct WorkspaceSubagentWorkerRequest: Equatable, Sendable, Hashable {
    var name: String
    var role: String

    init(name: String, role: String) {
        self.name = name
        self.role = role
    }
}

struct WorkspaceSubagentRunRequest: Equatable, Sendable, Hashable {
    var objective: String
    var workers: [WorkspaceSubagentWorkerRequest]

    init(objective: String, workers: [WorkspaceSubagentWorkerRequest]) {
        self.objective = objective
        self.workers = workers
    }
}

enum SlashSubagentCommandParser {
    private static let maxObjectiveCharacters = 220
    private static let maxWorkers = 6

    static func supports(_ name: String) -> Bool {
        ["subagent", "subagents", "parallel", "agents"].contains(name)
    }

    static func parse(_ argument: String) -> SlashCommand {
        let segments = argument
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { boundedLine(String($0), limit: maxObjectiveCharacters) }
            .filter { !$0.isEmpty }
        guard let objective = segments.first else {
            return .invalid("Usage: /subagents objective | Name: worker role | Verifier: worker role.")
        }

        let workerSegments = Array(segments.dropFirst())
        guard !workerSegments.isEmpty else {
            return .invalid("Add at least one subagent after `|`, for example /subagents audit auth | Security: inspect auth flow.")
        }
        guard workerSegments.count <= maxWorkers else {
            return .invalid("Subagent slash runs support \(maxWorkers) workers or fewer.")
        }

        let workers = workerSegments.enumerated().map { index, segment in
            worker(from: segment, fallbackIndex: index + 1)
        }
        return .subagents(WorkspaceSubagentRunRequest(objective: objective, workers: workers))
    }

    private static func worker(from segment: String, fallbackIndex: Int) -> WorkspaceSubagentWorkerRequest {
        let parts = segment.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let name = boundedLine(String(parts[0]), limit: 48)
            let role = boundedLine(String(parts[1]), limit: 140)
            if !name.isEmpty && !role.isEmpty {
                return WorkspaceSubagentWorkerRequest(name: name, role: role)
            }
        }
        return WorkspaceSubagentWorkerRequest(
            name: "Worker \(fallbackIndex)",
            role: boundedLine(segment, limit: 140)
        )
    }

    private static func boundedLine(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
