import Foundation
import QuillCodeTools

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

public struct WorkspaceWorktreeChoiceLoad: Sendable, Hashable {
    public var choices: [WorkspaceWorktreeChoice]
    public var errorMessage: String?

    public init(choices: [WorkspaceWorktreeChoice] = [], errorMessage: String? = nil) {
        self.choices = choices
        self.errorMessage = errorMessage
    }
}

enum WorkspaceWorktreeListSurfaceBuilder {
    static func choices(fromPorcelain stdout: String, selectedProjectPath: String?) -> [WorkspaceWorktreeChoice] {
        let selectedPath = selectedProjectPath.map(normalizedPath)
        return GitWorktreePorcelainParser.parse(stdout)
            .filter { selectedPath == nil || normalizedPath($0.path) != selectedPath }
            .map { entry in
                WorkspaceWorktreeChoice(
                    path: entry.path,
                    title: displayName(for: entry.path),
                    detail: detail(for: entry)
                )
            }
    }

    private static func displayName(for path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    private static func detail(for entry: GitWorktreeRecord) -> String {
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
