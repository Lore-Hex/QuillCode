import Foundation
import QuillCodeCore

struct WorkspaceSidebarBulkActionPlanner: Sendable, Hashable {
    struct ThreadContext: Sendable, Hashable {
        var id: UUID
        var projectID: UUID?

        init(_ thread: ChatThread) {
            self.id = thread.id
            self.projectID = thread.projectID
        }
    }

    enum FollowUpSelection: Sendable, Hashable {
        case unchanged
        case selectBestAfterRemoving(preferredProjectID: UUID?)
        case select(ThreadContext)
        case reconcileCurrent
    }

    enum Mutation: Sendable, Hashable {
        case pin([UUID])
        case unpin([UUID])
        case archive([UUID])
        case unarchive([UUID])
        case delete([UUID])
    }

    struct Plan: Sendable, Hashable {
        var nextSelection: SidebarSelectionState
        var mutation: Mutation?
        var followUpSelection: FollowUpSelection

        static func selectionOnly(_ nextSelection: SidebarSelectionState) -> Plan {
            Plan(
                nextSelection: nextSelection,
                mutation: nil,
                followUpSelection: .unchanged
            )
        }

        static func mutation(
            _ mutation: Mutation,
            followUpSelection: FollowUpSelection = .unchanged
        ) -> Plan {
            Plan(
                nextSelection: WorkspaceSidebarSelectionEngine.clear(),
                mutation: mutation,
                followUpSelection: followUpSelection
            )
        }
    }

    static func plan(
        kind: SidebarBulkActionKind,
        selection: SidebarSelectionState,
        orderedSidebarThreadIDs: [UUID],
        threads: [ChatThread],
        selectedThreadID: UUID?
    ) -> Plan? {
        let validThreadIDs = Set(threads.map(\.id))
        switch kind {
        case .select:
            return .selectionOnly(WorkspaceSidebarSelectionEngine.start(
                selecting: nil,
                state: selection,
                validThreadIDs: validThreadIDs
            ))
        case .selectAll:
            return .selectionOnly(WorkspaceSidebarSelectionEngine.selectAll(
                orderedThreadIDs: orderedSidebarThreadIDs
            ))
        case .clearSelection:
            return .selectionOnly(WorkspaceSidebarSelectionEngine.clear())
        case .pin, .unpin, .archive, .unarchive, .delete:
            break
        }

        let resolution = WorkspaceSidebarSelectionEngine.resolve(
            state: selection,
            orderedSidebarThreadIDs: orderedSidebarThreadIDs,
            validThreadIDs: validThreadIDs
        )
        let ids = resolution.selectedThreadIDs
        guard !ids.isEmpty else { return nil }

        switch kind {
        case .pin:
            return .mutation(.pin(ids))
        case .unpin:
            return .mutation(.unpin(ids))
        case .archive:
            return .mutation(
                .archive(ids),
                followUpSelection: selectedThreadContext(
                    selectedThreadID,
                    threads: threads,
                    selectedIDs: ids
                ).map {
                    .selectBestAfterRemoving(preferredProjectID: $0.projectID)
                } ?? .unchanged
            )
        case .unarchive:
            return .mutation(
                .unarchive(ids),
                followUpSelection: firstThreadContext(ids, threads: threads).map {
                    .select($0)
                } ?? .unchanged
            )
        case .delete:
            return .mutation(
                .delete(ids),
                followUpSelection: selectedThreadContext(
                    selectedThreadID,
                    threads: threads,
                    selectedIDs: ids
                ).map {
                    .selectBestAfterRemoving(preferredProjectID: $0.projectID)
                } ?? .reconcileCurrent
            )
        case .select, .selectAll, .clearSelection:
            return nil
        }
    }

    private static func selectedThreadContext(
        _ selectedThreadID: UUID?,
        threads: [ChatThread],
        selectedIDs: [UUID]
    ) -> ThreadContext? {
        guard let selectedThreadID,
              selectedIDs.contains(selectedThreadID),
              let thread = threads.first(where: { $0.id == selectedThreadID })
        else {
            return nil
        }
        return ThreadContext(thread)
    }

    private static func firstThreadContext(
        _ ids: [UUID],
        threads: [ChatThread]
    ) -> ThreadContext? {
        guard let id = ids.first,
              let thread = threads.first(where: { $0.id == id })
        else {
            return nil
        }
        return ThreadContext(thread)
    }
}
