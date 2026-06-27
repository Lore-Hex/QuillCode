import SwiftUI

struct QuillCodeSidebarThreadRowView: View {
    var item: SidebarItemSurface
    var isSelectionMode: Bool
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 6) {
            selectionToggle
            threadButton
            actionsMenu
        }
        .padding(10)
        .background(item.isSelected ? QuillCodePalette.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            .quillCodeFullRowButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
    }

    private var actionsMenu: some View {
        Menu {
            ForEach(item.actions) { action in
                Button(role: action.kind == .delete ? .destructive : nil) {
                    onThreadAction(action)
                } label: {
                    Text(action.kind.title)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .quillCodeIconButtonTarget()
                .foregroundStyle(QuillCodePalette.muted)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
    }

    private func toggleSelection() {
        onCommand(QuillCodeSidebarCommandAdapter.toggleSelectionCommand(for: item))
    }
}
