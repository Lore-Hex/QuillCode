import Foundation
import QuillCodeCore

struct ManagedWorktreeRetentionPlan: Sendable, Hashable {
    var activeManagedWorktreeCount: Int
    var targetRemovalCount: Int
    var candidateThreadIDs: [UUID]
}

enum ManagedWorktreeRetentionPlanner {
    static func plan(
        threads: [ChatThread],
        selectedThreadID: UUID?,
        runningThreadIDs: Set<UUID>,
        settings: ManagedWorktreeSettings
    ) -> ManagedWorktreeRetentionPlan {
        guard settings.automaticCleanupEnabled else {
            return ManagedWorktreeRetentionPlan(
                activeManagedWorktreeCount: 0,
                targetRemovalCount: 0,
                candidateThreadIDs: []
            )
        }

        let active = threads.filter { thread in
            thread.worktree?.isDisposableManagedWorktree == true
                && thread.worktree?.isResolvable == true
        }
        let bindingCounts = Dictionary(
            grouping: active,
            by: normalizedWorktreePath
        )
        .mapValues(\.count)
        let targetRemovalCount = max(0, active.count - settings.retentionLimit)
        let candidates = active
            .filter { thread in
                !thread.isPinned
                    && thread.id != selectedThreadID
                    && !runningThreadIDs.contains(thread.id)
                    && thread.worktree?.snapshot == nil
                    && bindingCounts[normalizedWorktreePath(thread)] == 1
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id)

        return ManagedWorktreeRetentionPlan(
            activeManagedWorktreeCount: active.count,
            targetRemovalCount: targetRemovalCount,
            candidateThreadIDs: candidates
        )
    }

    private static func normalizedWorktreePath(_ thread: ChatThread) -> String {
        URL(fileURLWithPath: thread.worktree?.path ?? "")
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
