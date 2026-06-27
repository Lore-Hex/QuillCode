import SwiftUI

struct QuillCodeSidebarThreadListView: View {
    var sidebar: SidebarSurface
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        if sidebar.visibleItems.isEmpty {
            Text(sidebar.emptyTitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !sidebar.pinnedItems.isEmpty {
                        QuillCodeSidebarThreadSectionView(
                            title: "Pinned",
                            items: sidebar.pinnedItems,
                            isSelectionMode: sidebar.isSelectionMode,
                            onSelectThread: onSelectThread,
                            onThreadAction: onThreadAction,
                            onCommand: onCommand
                        )
                    }
                    ForEach(sidebar.recentSections()) { section in
                        QuillCodeSidebarThreadSectionView(
                            title: section.title,
                            items: section.items,
                            isSelectionMode: sidebar.isSelectionMode,
                            onSelectThread: onSelectThread,
                            onThreadAction: onThreadAction,
                            onCommand: onCommand
                        )
                    }
                    if !sidebar.archivedItems.isEmpty {
                        QuillCodeSidebarThreadSectionView(
                            title: "Archived",
                            items: sidebar.archivedItems,
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

struct QuillCodeSidebarBulkActionsView: View {
    var selectionLabel: String
    var actions: [SidebarBulkActionSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectionLabel)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(actions) { action in
                        Button(action.title) {
                            onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: action))
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .quillCodeTextButtonTarget(minWidth: 56, radius: 8)
                        .background((action.isDestructive ? QuillCodePalette.red : QuillCodePalette.panel).opacity(action.isEnabled ? 1 : 0.45))
                        .foregroundStyle(action.isDestructive ? Color.white : QuillCodePalette.text)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .disabled(!action.isEnabled)
                        .buttonStyle(QuillCodePressableButtonStyle())
                    }
                }
            }
        }
        .padding(8)
        .background(QuillCodePalette.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct QuillCodeSidebarThreadSectionView: View {
    var title: String
    var items: [SidebarItemSurface]
    var isSelectionMode: Bool
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 4)
            ForEach(items) { item in
                QuillCodeSidebarThreadRowView(
                    item: item,
                    isSelectionMode: isSelectionMode,
                    onSelectThread: onSelectThread,
                    onThreadAction: onThreadAction,
                    onCommand: onCommand
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
