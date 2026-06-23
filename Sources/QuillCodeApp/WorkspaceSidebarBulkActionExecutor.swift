import Foundation
import QuillCodeCore

struct WorkspaceSidebarBulkActionExecutor: Sendable, Hashable {
    struct Result: Sendable, Hashable {
        var threads: [ChatThread]
        var selectedThreadID: UUID?
        var selectedProjectID: UUID?
        var nextSelection: SidebarSelectionState
        var changedThreads: [ChatThread]
        var removedThreads: [ChatThread]
        var shouldSaveProjects: Bool
        var shouldSyncTerminalSession: Bool
        var projectIDToTouch: UUID?
    }

    static func execute(
        _ plan: WorkspaceSidebarBulkActionPlanner.Plan,
        threads originalThreads: [ChatThread],
        projects: [ProjectRef],
        selectedThreadID originalSelectedThreadID: UUID?,
        selectedProjectID originalSelectedProjectID: UUID?,
        now: Date = Date()
    ) -> Result? {
        var threads = originalThreads
        var selectedThreadID = originalSelectedThreadID
        var selectedProjectID = originalSelectedProjectID
        var changedThreads: [ChatThread] = []
        var removedThreads: [ChatThread] = []
        var shouldSaveProjects = false

        if let mutation = plan.mutation {
            switch mutation {
            case .pin(let ids):
                changedThreads = setPinned(true, ids: ids, threads: &threads, now: now)
                shouldSaveProjects = !changedThreads.isEmpty
            case .unpin(let ids):
                changedThreads = setPinned(false, ids: ids, threads: &threads, now: now)
                shouldSaveProjects = !changedThreads.isEmpty
            case .archive(let ids):
                guard let result = WorkspaceThreadLifecycleEngine.archiveThreads(
                    ids,
                    threads: &threads,
                    now: now
                ) else {
                    return nil
                }
                changedThreads = result.changedThreads
                shouldSaveProjects = true
            case .unarchive(let ids):
                guard let result = WorkspaceThreadLifecycleEngine.unarchiveThreads(
                    ids,
                    threads: &threads,
                    now: now
                ) else {
                    return nil
                }
                changedThreads = result.changedThreads
                shouldSaveProjects = true
            case .delete(let ids):
                guard let result = WorkspaceThreadLifecycleEngine.deleteThreads(
                    ids,
                    threads: &threads
                ) else {
                    return nil
                }
                removedThreads = result.removedThreads
                shouldSaveProjects = true
            }
        }

        let followUp = apply(
            plan.followUpSelection,
            removing: plan.mutation?.targetIDs ?? [],
            selectedThreadID: &selectedThreadID,
            selectedProjectID: &selectedProjectID,
            threads: threads,
            projects: projects
        )

        return Result(
            threads: threads,
            selectedThreadID: selectedThreadID,
            selectedProjectID: selectedProjectID,
            nextSelection: plan.nextSelection,
            changedThreads: changedThreads,
            removedThreads: removedThreads,
            shouldSaveProjects: shouldSaveProjects,
            shouldSyncTerminalSession: followUp.shouldSyncTerminalSession,
            projectIDToTouch: followUp.projectIDToTouch
        )
    }

    private static func setPinned(
        _ isPinned: Bool,
        ids: [UUID],
        threads: inout [ChatThread],
        now: Date
    ) -> [ChatThread] {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return [] }

        var changedThreads: [ChatThread] = []
        for index in threads.indices where targetIDs.contains(threads[index].id) {
            if isPinned, threads[index].isArchived {
                continue
            }
            threads[index].isPinned = isPinned
            threads[index].updatedAt = now
            changedThreads.append(threads[index])
        }
        return changedThreads
    }

    private struct FollowUpResult: Sendable, Hashable {
        var shouldSyncTerminalSession: Bool = false
        var projectIDToTouch: UUID?
    }

    private static func apply(
        _ followUpSelection: WorkspaceSidebarBulkActionPlanner.FollowUpSelection,
        removing ids: [UUID],
        selectedThreadID: inout UUID?,
        selectedProjectID: inout UUID?,
        threads: [ChatThread],
        projects: [ProjectRef]
    ) -> FollowUpResult {
        switch followUpSelection {
        case .unchanged:
            return FollowUpResult()
        case .selectBestAfterRemoving(let preferredProjectID):
            let selection = WorkspaceProjectEngine.selectionAfterRemovingThreads(
                ids,
                preferredProjectID: preferredProjectID,
                projects: projects,
                threads: threads
            )
            selectedThreadID = selection.threadID
            selectedProjectID = selection.projectID
            return FollowUpResult(shouldSyncTerminalSession: true)
        case .select(let context):
            let projectID = knownProjectID(context.projectID, projects: projects)
            selectedThreadID = context.id
            selectedProjectID = projectID
            return FollowUpResult(
                shouldSyncTerminalSession: true,
                projectIDToTouch: projectID
            )
        case .reconcileCurrent:
            if let selectedThreadID,
               let selectedThread = threads.first(where: { $0.id == selectedThreadID }) {
                selectedProjectID = knownProjectID(selectedThread.projectID, projects: projects)
            } else {
                selectedProjectID = knownProjectID(selectedProjectID, projects: projects)
            }
            return FollowUpResult()
        }
    }

    private static func knownProjectID(_ id: UUID?, projects: [ProjectRef]) -> UUID? {
        guard let id, projects.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}

private extension WorkspaceSidebarBulkActionPlanner.Mutation {
    var targetIDs: [UUID] {
        switch self {
        case .pin(let ids),
             .unpin(let ids),
             .archive(let ids),
             .unarchive(let ids),
             .delete(let ids):
            return ids
        }
    }
}
