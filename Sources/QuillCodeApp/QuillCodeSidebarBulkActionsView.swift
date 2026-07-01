import SwiftUI

struct QuillCodeSidebarBulkActionsView: View {
    var selectionLabel: String
    var actions: [SidebarBulkActionSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectionLabel)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            actionScroller
        }
        .padding(8)
        .background(QuillCodePalette.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                ForEach(actions) { action in
                    QuillCodeSidebarBulkActionButton(action: action, onCommand: onCommand)
                }
            }
        }
    }
}

private struct QuillCodeSidebarBulkActionButton: View {
    var action: SidebarBulkActionSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        Button(action.title) {
            onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: action))
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .quillCodeTextButtonTarget(minWidth: 56, radius: 8)
        .background(backgroundColor.opacity(action.isEnabled ? 1 : 0.45))
        .foregroundStyle(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .disabled(!action.isEnabled)
        .buttonStyle(QuillCodePressableButtonStyle())
    }

    private var backgroundColor: Color {
        action.isDestructive ? QuillCodePalette.red : QuillCodePalette.panel
    }

    private var foregroundColor: Color {
        action.isDestructive ? Color.white : QuillCodePalette.text
    }
}
