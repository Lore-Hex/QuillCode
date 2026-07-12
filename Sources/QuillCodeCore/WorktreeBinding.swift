import Foundation

/// Binds a thread to a git worktree so its agent run operates in an isolated working directory and
/// branch, instead of sharing the project root with every other thread. `nil` on a thread means
/// "inherit the project root" (every thread written before this existed, and any un-forked thread).
///
/// `base` is the ref the worktree was forked off — the target a later land+prune merges back into.
public struct WorktreeBinding: Codable, Sendable, Hashable {
    /// Absolute path to the worktree directory (a sibling of the project root).
    public var path: String
    /// The branch checked out in the worktree, or an empty string for a detached managed task.
    public var branch: String
    /// The ref this worktree was created from (its land-back target). nil when unknown.
    public var base: String?

    public init(path: String, branch: String, base: String? = nil) {
        self.path = path
        self.branch = branch
        self.base = base
    }

    /// A binding is only usable if it names a real directory; a dangling path means the worktree was
    /// removed out from under the thread, in which case the run should fall back to the project root.
    public var isResolvable: Bool {
        !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }
}
