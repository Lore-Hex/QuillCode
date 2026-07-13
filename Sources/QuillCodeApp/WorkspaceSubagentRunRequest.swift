import Foundation
import QuillCodeCore

struct WorkspaceSubagentWorkerRequest: Codable, Equatable, Sendable, Hashable {
    var name: String
    var role: String
    var dependsOn: [String]
    var groupPath: [String]

    init(name: String, role: String, dependsOn: [String] = [], groupPath: [String] = []) {
        self.name = name
        self.role = role
        self.dependsOn = dependsOn
        self.groupPath = groupPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(String.self, forKey: .role)
        dependsOn = try container.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        groupPath = try container.decodeIfPresent([String].self, forKey: .groupPath) ?? []
    }
}

struct WorkspaceSubagentRunRequest: Codable, Equatable, Sendable, Hashable {
    var objective: String
    var workers: [WorkspaceSubagentWorkerRequest]
    /// Optional cap on how many workers run at once within a dependency wave.
    /// `nil` means unbounded (every ready worker fans out together).
    var maxConcurrentWorkers: Int?

    init(
        objective: String,
        workers: [WorkspaceSubagentWorkerRequest],
        maxConcurrentWorkers: Int? = nil
    ) {
        self.objective = objective
        self.workers = workers
        self.maxConcurrentWorkers = maxConcurrentWorkers
    }
}

enum WorkspaceSubagentRunToolRequestDecoder {
    private static let maxObjectiveCharacters = 220
    private static let maxWorkerCount = 6
    private static let maxWorkerNameCharacters = 72
    private static let maxRoleCharacters = 140
    private static let maxDependencyCharacters = 72
    private static let maxGroupDepth = 4
    private static let maxGroupComponentCharacters = 32

    static func decode(_ call: ToolCall) throws -> WorkspaceSubagentRunRequest {
        guard call.name == ToolDefinition.subagentsRun.name else {
            throw WorkspaceSubagentRunToolRequestError.unknownTool(call.name)
        }
        let decoded: WorkspaceSubagentRunRequest
        do {
            decoded = try JSONHelpers.decode(WorkspaceSubagentRunRequest.self, from: call.argumentsJSON)
        } catch {
            throw WorkspaceSubagentRunToolRequestError.invalidJSON
        }

        let objective = boundedLine(decoded.objective, limit: maxObjectiveCharacters)
        guard !objective.isEmpty else {
            throw WorkspaceSubagentRunToolRequestError.emptyObjective
        }
        guard !decoded.workers.isEmpty else {
            throw WorkspaceSubagentRunToolRequestError.emptyWorkers
        }
        guard decoded.workers.count <= maxWorkerCount else {
            throw WorkspaceSubagentRunToolRequestError.tooManyWorkers(
                decoded.workers.count,
                maxWorkerCount
            )
        }
        if let limit = decoded.maxConcurrentWorkers,
           !(1...maxWorkerCount).contains(limit) {
            throw WorkspaceSubagentRunToolRequestError.invalidConcurrency(limit)
        }

        let workers = try decoded.workers.map(normalizedWorker)
        let names = workers.map { $0.name.lowercased() }
        guard Set(names).count == names.count else {
            throw WorkspaceSubagentRunToolRequestError.duplicateWorkerName
        }
        let availableNames = Set(names)
        for worker in workers {
            let workerName = worker.name.lowercased()
            for dependency in worker.dependsOn {
                let dependencyName = dependency.lowercased()
                guard dependencyName != workerName else {
                    throw WorkspaceSubagentRunToolRequestError.selfDependency(worker.name)
                }
                guard availableNames.contains(dependencyName) else {
                    throw WorkspaceSubagentRunToolRequestError.unknownDependency(
                        worker: worker.name,
                        dependency: dependency
                    )
                }
            }
        }

        return WorkspaceSubagentRunRequest(
            objective: objective,
            workers: workers,
            maxConcurrentWorkers: decoded.maxConcurrentWorkers
        )
    }

    private static func normalizedWorker(
        _ worker: WorkspaceSubagentWorkerRequest
    ) throws -> WorkspaceSubagentWorkerRequest {
        let name = boundedLine(worker.name, limit: maxWorkerNameCharacters)
        let role = boundedLine(worker.role, limit: maxRoleCharacters)
        guard !name.isEmpty else {
            throw WorkspaceSubagentRunToolRequestError.emptyWorkerName
        }
        guard !role.isEmpty else {
            throw WorkspaceSubagentRunToolRequestError.emptyWorkerRole(name)
        }
        guard worker.dependsOn.count <= maxWorkerCount else {
            throw WorkspaceSubagentRunToolRequestError.tooManyDependencies(
                worker: name,
                count: worker.dependsOn.count,
                limit: maxWorkerCount
            )
        }
        guard worker.groupPath.count <= maxGroupDepth else {
            throw WorkspaceSubagentRunToolRequestError.groupPathTooDeep(
                worker: name,
                count: worker.groupPath.count,
                limit: maxGroupDepth
            )
        }
        let dependencies = worker.dependsOn
            .map { boundedLine($0, limit: maxDependencyCharacters) }
            .filter { !$0.isEmpty }
        let groupPath = worker.groupPath
            .map { boundedLine($0, limit: maxGroupComponentCharacters) }
            .filter { !$0.isEmpty }
        return WorkspaceSubagentWorkerRequest(
            name: name,
            role: role,
            dependsOn: stableUnique(dependencies),
            groupPath: groupPath
        )
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func boundedLine(_ text: String, limit: Int) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum WorkspaceSubagentRunToolRequestError: LocalizedError {
    case unknownTool(String)
    case invalidJSON
    case emptyObjective
    case emptyWorkers
    case tooManyWorkers(Int, Int)
    case invalidConcurrency(Int)
    case emptyWorkerName
    case emptyWorkerRole(String)
    case tooManyDependencies(worker: String, count: Int, limit: Int)
    case groupPathTooDeep(worker: String, count: Int, limit: Int)
    case duplicateWorkerName
    case selfDependency(String)
    case unknownDependency(worker: String, dependency: String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .invalidJSON:
            return "Run Subagents needs objective, workers, and optional maxConcurrentWorkers JSON."
        case .emptyObjective:
            return "Run Subagents needs a non-empty shared objective."
        case .emptyWorkers:
            return "Run Subagents needs at least one worker."
        case .tooManyWorkers(let count, let limit):
            return "Run Subagents received \(count) workers; keep it to \(limit) or fewer."
        case .invalidConcurrency(let value):
            return "Run Subagents concurrency must be between 1 and 6, not \(value)."
        case .emptyWorkerName:
            return "Every delegated worker needs a short name."
        case .emptyWorkerRole(let name):
            return "Delegated worker \(name) needs a precise role."
        case .tooManyDependencies(let worker, let count, let limit):
            return "Delegated worker \(worker) has \(count) dependencies; keep it to \(limit) or fewer."
        case .groupPathTooDeep(let worker, let count, let limit):
            return "Delegated worker \(worker) has a \(count)-level group path; keep it to \(limit) levels or fewer."
        case .duplicateWorkerName:
            return "Delegated worker names must be unique."
        case .selfDependency(let name):
            return "Delegated worker \(name) cannot depend on itself."
        case .unknownDependency(let worker, let dependency):
            return "Delegated worker \(worker) depends on unknown worker \(dependency)."
        }
    }
}

enum SlashSubagentCommandParser {
    private static let maxObjectiveCharacters = 220
    private static let maxGroupDepth = 4
    private static let maxGroupPathComponentCharacters = 32
    private static let maxWorkerNameCharacters = 72
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
        let (resolvedObjective, limit) = objectiveAndConcurrency(from: objective)
        return .subagents(WorkspaceSubagentRunRequest(
            objective: resolvedObjective,
            workers: workers,
            maxConcurrentWorkers: limit
        ))
    }

    /// Extracts an optional leading `xN` concurrency token from the objective, e.g.
    /// `x2 ship release` -> ("ship release", 2). The token is only honored when it is the first
    /// whitespace-delimited word, fully matches `x` followed by digits, and leaves a non-empty
    /// objective behind, so ordinary objectives like `xerox audit` are untouched.
    private static func objectiveAndConcurrency(from objective: String) -> (objective: String, limit: Int?) {
        let parts = objective.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let limit = concurrencyToken(String(parts[0])) else {
            return (objective, nil)
        }
        let remaining = boundedLine(String(parts[1]), limit: maxObjectiveCharacters)
        guard !remaining.isEmpty else { return (objective, nil) }
        return (remaining, limit)
    }

    private static func concurrencyToken(_ token: String) -> Int? {
        let lowered = token.lowercased()
        guard lowered.hasPrefix("x"), lowered.count >= 2, lowered.count <= 3 else { return nil }
        guard let value = Int(lowered.dropFirst()), value >= 1 else { return nil }
        return min(value, maxWorkers)
    }

    private static func worker(from segment: String, fallbackIndex: Int) -> WorkspaceSubagentWorkerRequest {
        let parts = segment.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let (rawName, rawDependencies) = nameAndDependencies(from: String(parts[0]))
            let (name, groupPath) = nestedName(from: rawName)
            let dependsOn = rawDependencies.map {
                qualifiedDependencyName($0, currentGroupPath: groupPath)
            }
            let role = boundedLine(String(parts[1]), limit: 140)
            if !name.isEmpty && !role.isEmpty {
                return WorkspaceSubagentWorkerRequest(
                    name: name,
                    role: role,
                    dependsOn: dependsOn,
                    groupPath: groupPath
                )
            }
        }
        return WorkspaceSubagentWorkerRequest(
            name: "Worker \(fallbackIndex)",
            role: boundedLine(segment, limit: 140)
        )
    }

    /// Splits a worker name segment into its display name and any `after`-declared
    /// dependencies, e.g. `Verifier after Builder, Linter` -> ("Verifier", ["Builder", "Linter"]).
    /// The `after` keyword is matched case-insensitively and only when surrounded by spaces so
    /// names that merely contain the substring (e.g. "Drafter") are left intact.
    private static func nameAndDependencies(from rawName: String) -> (name: String, dependsOn: [String]) {
        let collapsed = boundedLine(rawName, limit: 200)
        guard let afterRange = collapsed.range(of: " after ", options: .caseInsensitive) else {
            return (boundedLine(collapsed, limit: maxWorkerNameCharacters), [])
        }
        let name = boundedLine(String(collapsed[collapsed.startIndex..<afterRange.lowerBound]), limit: maxWorkerNameCharacters)
        let dependencyList = String(collapsed[afterRange.upperBound...])
        let dependsOn = dependencyList
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { boundedLine(String($0), limit: 48) }
            .filter { !$0.isEmpty }
        guard !name.isEmpty else {
            return (boundedLine(collapsed, limit: maxWorkerNameCharacters), [])
        }
        return (name, Array(dependsOn.prefix(maxWorkers)))
    }

    /// Parses `Group/Subgroup/Worker` as a hierarchical subagent path while keeping the joined
    /// path as the stable worker name used by dependency resolution and progress IDs.
    private static func nestedName(from rawName: String) -> (name: String, groupPath: [String]) {
        let components = rawName
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { boundedLine(String($0), limit: maxGroupPathComponentCharacters) }
            .filter { !$0.isEmpty }
        guard components.count > 1 else {
            return (boundedLine(rawName, limit: maxWorkerNameCharacters), [])
        }
        let limitedComponents = Array(components.prefix(maxGroupDepth + 1))
        let groupPath = Array(limitedComponents.dropLast())
        let name = boundedLine(limitedComponents.joined(separator: "/"), limit: maxWorkerNameCharacters)
        return (name, groupPath)
    }

    /// `Verifier after Builder` inside `Frontend/Verifier` resolves to `Frontend/Builder`.
    /// Authors can still depend on another group by writing the full path explicitly.
    private static func qualifiedDependencyName(_ rawName: String, currentGroupPath: [String]) -> String {
        let dependency = nestedName(from: rawName)
        if !dependency.groupPath.isEmpty || currentGroupPath.isEmpty {
            return dependency.name
        }
        return boundedLine((currentGroupPath + [dependency.name]).joined(separator: "/"), limit: maxWorkerNameCharacters)
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
