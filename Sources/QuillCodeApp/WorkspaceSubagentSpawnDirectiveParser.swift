import Foundation

/// Parses optional delegation directives a subagent worker may emit in its result text, turning them
/// into child worker requests for the scheduler's recursive `spawn` path. A worker delegates by
/// including one or more `[[DELEGATE: <name> | <role>]]` markers anywhere in its result.
///
/// The marker is bracket-delimited (not line-based) on purpose: `AgentWorkspaceSubagentWorker.run`
/// collapses whitespace in the model's reply, which would destroy line structure — but `[[DELEGATE:
/// ... ]]` survives whitespace collapse intact. Parsing is bounded (children per worker, name/role
/// lengths) and de-duplicated by name; the scheduler additionally caps recursion depth and total jobs.
///
/// A marker is honored wherever it appears in a worker's result, including text the worker echoed from
/// its input. Spawned children still run through the same workspace boundary and safety reviewer as
/// their parent, while the parser and scheduler cap children, recursion depth, and total jobs. Those
/// bounds keep an echoed or malformed directive from creating unbounded work.
enum WorkspaceSubagentSpawnDirectiveParser {
    static let openMarker = "[[DELEGATE:"
    static let closeMarker = "]]"
    static let maxChildrenPerWorker = 3
    static let maxNameCharacters = 72
    static let maxRoleCharacters = 160

    static func parse(_ text: String) -> [WorkspaceSubagentWorkerRequest] {
        var requests: [WorkspaceSubagentWorkerRequest] = []
        var seen = Set<String>()
        // Split on the open marker; every segment after the first begins inside a directive.
        for segment in text.components(separatedBy: openMarker).dropFirst() {
            guard let close = segment.range(of: closeMarker) else { continue }
            let inner = segment[segment.startIndex..<close.lowerBound]
            let parts = inner.components(separatedBy: "|")
            guard parts.count >= 2 else { continue }
            // Split on the FIRST pipe only: the name is a short label that never contains a pipe, but
            // the role is free-form prose that often does (`compile | link`, `grep foo | wc -l`,
            // `build | test | deploy`). Rejoining the remainder keeps such roles intact instead of
            // silently dropping the whole directive.
            // `/` is the scheduler's group-path separator and `#` its dedup-suffix marker; keep child
            // names clear of both so namespacing stays unambiguous.
            let name = bounded(parts[0], limit: maxNameCharacters)
                .replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: "#", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let role = bounded(parts.dropFirst().joined(separator: "|"), limit: maxRoleCharacters)
            guard !name.isEmpty, !role.isEmpty else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            requests.append(WorkspaceSubagentWorkerRequest(name: name, role: role))
            if requests.count >= maxChildrenPerWorker { break }
        }
        return requests
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }
}
