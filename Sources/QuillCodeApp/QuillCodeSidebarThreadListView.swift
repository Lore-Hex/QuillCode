import SwiftUI

struct QuillCodeSidebarThreadListView: View {
    var sidebar: SidebarSurface
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        let sections = sidebar.threadSections

        if sections.isEmpty {
            Text(sidebar.emptyTitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(sections) { section in
                        QuillCodeSidebarThreadSectionView(
                            section: section,
                            isSelectionMode: sidebar.isSelectionMode,
                            onSelectThread: onSelectThread,
                            onThreadAction: onThreadAction,
                            onCommand: onCommand
                        )
                    }
                }
            }
        }
    }
}

private extension SidebarSurface {
    var threadSections: [SidebarThreadSectionSurface] {
        compactThreadSection(title: "Pinned", items: pinnedItems)
            + recentSections()
            + compactThreadSection(title: "Archived", items: archivedItems)
    }

    func compactThreadSection(
        title: String,
        items: [SidebarItemSurface]
    ) -> [SidebarThreadSectionSurface] {
        guard !items.isEmpty else { return [] }
        return [SidebarThreadSectionSurface(title: title, items: items)]
    }
}
