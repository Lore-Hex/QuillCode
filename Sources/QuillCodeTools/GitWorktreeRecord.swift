import Foundation

public struct GitWorktreeRecord: Sendable, Hashable {
    public var path: String
    public var branch: String?
    public var isDetached: Bool
    public var isBare: Bool

    public init(
        path: String,
        branch: String? = nil,
        isDetached: Bool = false,
        isBare: Bool = false
    ) {
        self.path = path
        self.branch = branch
        self.isDetached = isDetached
        self.isBare = isBare
    }
}

public enum GitWorktreePorcelainParser {
    public static func parse(_ output: String) -> [GitWorktreeRecord] {
        var records: [GitWorktreeRecord] = []
        var current: GitWorktreeRecord?

        func flush() {
            if let current {
                records.append(current)
            }
            current = nil
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("worktree ") {
                flush()
                let path = String(line.dropFirst("worktree ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    current = GitWorktreeRecord(path: path)
                }
            } else if line.hasPrefix("branch ") {
                current?.branch = branchName(String(line.dropFirst("branch ".count)))
            } else if line == "detached" {
                current?.isDetached = true
            } else if line == "bare" {
                current?.isBare = true
            }
        }
        flush()
        return records
    }

    private static func branchName(_ value: String) -> String {
        let branch = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "refs/heads/"
        return branch.hasPrefix(prefix) ? String(branch.dropFirst(prefix.count)) : branch
    }
}
