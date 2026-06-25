import Foundation
import QuillCodeCore

public struct WorkspaceWorktreeChoice: Sendable, Hashable, Identifiable {
    public var path: String
    public var title: String
    public var detail: String

    public var id: String { path }

    public init(path: String, title: String, detail: String) {
        self.path = path
        self.title = title
        self.detail = detail
    }
}

public struct WorkspaceWorktreeChoiceLoadResult: Sendable, Hashable {
    public var choices: [WorkspaceWorktreeChoice]
    public var error: String?

    public init(choices: [WorkspaceWorktreeChoice], error: String? = nil) {
        self.choices = choices
        self.error = error
    }

    public static func fromToolResult(
        _ result: ToolResult,
        selectedProjectPath: String?
    ) -> WorkspaceWorktreeChoiceLoadResult {
        guard result.ok else {
            let message = result.error
                ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Could not load git worktrees."
            return WorkspaceWorktreeChoiceLoadResult(choices: [], error: message)
        }
        return WorkspaceWorktreeChoiceLoadResult(
            choices: WorkspaceWorktreeListSurfaceBuilder.choices(
                fromPorcelain: result.stdout,
                selectedProjectPath: selectedProjectPath
            )
        )
    }
}

enum WorkspaceWorktreeListSurfaceBuilder {
    static func choices(fromPorcelain stdout: String, selectedProjectPath: String?) -> [WorkspaceWorktreeChoice] {
        let selectedPath = selectedProjectPath.map(normalizedPath)
        return parse(stdout)
            .filter { selectedPath == nil || normalizedPath($0.path) != selectedPath }
            .map { entry in
                WorkspaceWorktreeChoice(
                    path: entry.path,
                    title: displayName(for: entry.path),
                    detail: detail(for: entry)
                )
            }
    }

    private static func parse(_ stdout: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var current: WorktreeEntry?

        func flush() {
            if let current {
                entries.append(current)
            }
            current = nil
        }

        for rawLine in stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("worktree ") {
                flush()
                let path = String(line.dropFirst("worktree ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    current = WorktreeEntry(path: path)
                }
                continue
            }
            guard current != nil else { continue }
            if line.hasPrefix("branch ") {
                current?.branch = displayBranch(String(line.dropFirst("branch ".count)))
            } else if line == "detached" {
                current?.isDetached = true
            } else if line == "bare" {
                current?.isBare = true
            }
        }
        flush()
        return entries
    }

    private static func displayName(for path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    private static func displayBranch(_ branch: String) -> String {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("refs/heads/") {
            return String(trimmed.dropFirst("refs/heads/".count))
        }
        return trimmed
    }

    private static func detail(for entry: WorktreeEntry) -> String {
        if let branch = entry.branch, !branch.isEmpty {
            return branch
        }
        if entry.isDetached {
            return "Detached HEAD"
        }
        if entry.isBare {
            return "Bare worktree"
        }
        return "Registered worktree"
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private struct WorktreeEntry: Equatable {
    var path: String
    var branch: String?
    var isDetached = false
    var isBare = false
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
