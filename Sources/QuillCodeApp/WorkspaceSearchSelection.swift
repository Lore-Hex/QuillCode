import Foundation

struct WorkspaceSearchSelection: Equatable {
    private(set) var highlightedThreadID: UUID?

    mutating func select(_ item: SidebarItemSurface) {
        highlightedThreadID = item.id
    }

    mutating func reconcile(with items: [SidebarItemSurface], preferredID: UUID? = nil) {
        guard !items.isEmpty else {
            highlightedThreadID = nil
            return
        }

        if let preferredID, items.contains(where: { $0.id == preferredID }) {
            highlightedThreadID = preferredID
            return
        }

        if let highlightedThreadID, items.contains(where: { $0.id == highlightedThreadID }) {
            return
        }

        highlightedThreadID = items[0].id
    }

    mutating func move(by delta: Int, in items: [SidebarItemSurface]) {
        guard !items.isEmpty else {
            highlightedThreadID = nil
            return
        }

        let currentIndex = highlightedThreadID.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = positiveModulo(currentIndex + delta, items.count)
        highlightedThreadID = items[nextIndex].id
    }

    func selectedItem(in items: [SidebarItemSurface]) -> SidebarItemSurface? {
        items.first { $0.id == highlightedThreadID } ?? items.first
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0)
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
