import Foundation
import QuillCodeCore

/// Selects disposable managed worktrees for oldest-first cleanup without performing I/O.
enum ManagedWorktreeRetentionPolicy {
    static func removalCandidates(
        threads: [ChatThread],
        runningThreadIDs: Set<UUID>,
        selectedThreadID: UUID?,
        retentionLimit: Int?,
        pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [UUID] {
        guard let retentionLimit, retentionLimit > 0 else { return [] }

        let managedThreads = threads.filter { thread in
            guard let binding = thread.worktree else { return false }
            return binding.isDisposableManagedWorktree
                && !binding.path.isEmpty
                && pathExists(binding.path)
        }
        let groups = Dictionary(grouping: managedThreads) { thread in
            URL(fileURLWithPath: thread.worktree?.path ?? "")
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
        }
        let removalCount = max(0, groups.count - retentionLimit)
        guard removalCount > 0 else { return [] }

        let removable = groups.values.compactMap { group -> ChatThread? in
            guard group.count == 1, let thread = group.first else { return nil }
            guard !thread.isPinned,
                  thread.id != selectedThreadID,
                  !runningThreadIDs.contains(thread.id) else {
                return nil
            }
            return thread
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return removable.prefix(removalCount).map(\.id)
    }
}
