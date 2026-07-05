import SwiftUI

struct QuillCodeSidebarThreadRowView: View {
    var item: SidebarItemSurface
    var isSelectionMode: Bool
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.minimumTargetClearance) {
            selectionToggle
            threadButton
            actionsMenu
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 0)
    }

    @ViewBuilder
    private var selectionToggle: some View {
        if isSelectionMode {
            Button {
                toggleSelection()
            } label: {
                Image(systemName: item.isBulkSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.isBulkSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .quillCodeIconButtonTarget()
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityLabel(item.isBulkSelected ? "Deselect \(item.title)" : "Select \(item.title)")
        }
    }

    private var threadButton: some View {
        Button {
            if isSelectionMode {
                toggleSelection()
            } else {
                onSelectThread(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13.25, weight: .medium))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11.25, weight: .regular))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            .quillCodeSidebarRowChrome(background: item.isSelected ? QuillCodePalette.selection : Color.clear)
        }
        .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
    }

    private var actionsMenu: some View {
        Menu {
            ForEach(item.actions) { action in
                Button(role: action.kind == .delete ? .destructive : nil) {
                    onThreadAction(action)
                } label: {
                    Text(action.kind.title)
                }
                .quillCodePlatformMenuItemTarget(reason: "AppKit owns thread action menu row geometry; the ellipsis trigger carries the custom hit-target contract.")
            }
        } label: {
            Image(systemName: "ellipsis")
                .quillCodeIconButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Thread actions")
        .accessibilityLabel("Thread actions for \(item.title)")
    }

    private func toggleSelection() {
        onCommand(QuillCodeSidebarCommandAdapter.toggleSelectionCommand(for: item))
    }
}
