import Foundation

public struct SidebarSelectionState: Sendable, Hashable {
    public var isActive: Bool
    public var selectedThreadIDs: Set<UUID>

    public init(isActive: Bool = false, selectedThreadIDs: Set<UUID> = []) {
        self.isActive = isActive
        self.selectedThreadIDs = selectedThreadIDs
    }
}

struct WorkspaceSidebarSelectionEngine {
    struct Resolution: Sendable, Hashable {
        var state: SidebarSelectionState
        var selectedThreadIDs: [UUID]
    }

    static func start(
        selecting id: UUID?,
        state: SidebarSelectionState,
        validThreadIDs: Set<UUID>
    ) -> SidebarSelectionState {
        var next = state
        next.isActive = true
        if let id, validThreadIDs.contains(id) {
            next.selectedThreadIDs.insert(id)
        }
        return next
    }

    static func clear() -> SidebarSelectionState {
        SidebarSelectionState()
    }

    static func selectAll(orderedThreadIDs: [UUID]) -> SidebarSelectionState {
        guard !orderedThreadIDs.isEmpty else {
            return clear()
        }
        return SidebarSelectionState(
            isActive: true,
            selectedThreadIDs: Set(orderedThreadIDs)
        )
    }

    static func toggle(
        _ id: UUID,
        state: SidebarSelectionState,
        validThreadIDs: Set<UUID>
    ) -> SidebarSelectionState? {
        guard validThreadIDs.contains(id) else {
            return nil
        }

        var next = state
        next.isActive = true
        if next.selectedThreadIDs.contains(id) {
            next.selectedThreadIDs.remove(id)
        } else {
            next.selectedThreadIDs.insert(id)
        }
        return next
    }

    static func resolve(
        state: SidebarSelectionState,
        orderedSidebarThreadIDs: [UUID],
        validThreadIDs: Set<UUID>
    ) -> Resolution {
        var next = state
        next.selectedThreadIDs = next.selectedThreadIDs.intersection(validThreadIDs)
        guard !next.selectedThreadIDs.isEmpty else {
            return Resolution(state: next, selectedThreadIDs: [])
        }

        let orderedSelectedIDs = orderedSidebarThreadIDs
            .filter { next.selectedThreadIDs.contains($0) }
        return Resolution(state: next, selectedThreadIDs: orderedSelectedIDs)
    }
}
