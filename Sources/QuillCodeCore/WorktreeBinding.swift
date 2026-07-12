import Foundation

public enum WorktreeExecutionLocation: String, Codable, Sendable, Hashable {
    case local
    case worktree
}

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
    /// Where the task currently runs. The associated worktree remains stable across handoffs.
    public var location: WorktreeExecutionLocation

    public init(
        path: String,
        branch: String,
        base: String? = nil,
        location: WorktreeExecutionLocation = .worktree
    ) {
        self.path = path
        self.branch = branch
        self.base = base
        self.location = location
    }

    /// A binding is only usable if it names a real directory; a dangling path means the worktree was
    /// removed out from under the thread, in which case the run should fall back to the project root.
    public var isResolvable: Bool {
        !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }

    public var usesWorktree: Bool {
        location == .worktree && isResolvable
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case branch
        case base
        case location
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.branch = try container.decode(String.self, forKey: .branch)
        self.base = try container.decodeIfPresent(String.self, forKey: .base)
        self.location = try container.decodeIfPresent(WorktreeExecutionLocation.self, forKey: .location)
            ?? .worktree
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(branch, forKey: .branch)
        try container.encodeIfPresent(base, forKey: .base)
        try container.encode(location, forKey: .location)
    }
}
