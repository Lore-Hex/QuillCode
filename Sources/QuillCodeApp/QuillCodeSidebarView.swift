import SwiftUI

struct QuillCodeSidebarView: View {
    var projects: ProjectListSurface
    var sidebar: SidebarSurface
    var commands: [WorkspaceCommandSurface]
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void
    var onMoveProjectBefore: (UUID, UUID) -> Bool
    var onMoveProjectToBottom: (UUID) -> Bool
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void
    /// Opening a thread from the Attention section lands on its return digest, so it is routed
    /// separately from an ordinary thread selection. Defaults to a plain selection when unset.
    var onOpenAttentionDigest: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: QuillCodeMetrics.sidebarSectionSpacing) {
            QuillCodeSidebarActionsView(commands: commands, onCommand: onCommand)
            if showsThreadHeader {
                Divider()
                threadHeader
                if sidebar.isSelectionMode {
                    QuillCodeSidebarBulkActionsView(
                        selectionLabel: sidebar.selectionLabel,
                        actions: sidebar.bulkActions.filter { $0.kind != .clearSelection },
                        onCommand: onCommand
                    )
                }
            }
            if !sidebar.attention.isEmpty {
                QuillCodeAttentionSectionView(
                    attention: sidebar.attention,
                    onSelectThread: onOpenAttentionDigest,
                    onCommand: onCommand
                )
                Divider()
            }
            QuillCodeSidebarThreadListView(
                sidebar: sidebar,
                onSelectThread: onSelectThread,
                onThreadAction: onThreadAction,
                onCommand: onCommand
            )
            Divider()
            QuillCodeProjectListView(
                projects: projects,
                onSelectProject: onSelectProject,
                onAddProjectRequested: onAddProjectRequested,
                onProjectAction: onProjectAction,
                onMoveProjectBefore: onMoveProjectBefore,
                onMoveProjectToBottom: onMoveProjectToBottom
            )
            Spacer(minLength: 0)
            QuillCodeSidebarUtilityActionsView(commands: commands, onCommand: onCommand)
        }
        .padding(.top, QuillCodeMetrics.sidebarVerticalInset)
        .padding(.bottom, QuillCodeMetrics.sidebarVerticalInset)
        .padding(.leading, QuillCodeMetrics.sidebarLeadingInset)
        .padding(.trailing, QuillCodeMetrics.sidebarTrailingInset)
        .background(QuillCodePalette.sidebar)
    }

    private var showsThreadHeader: Bool {
        !sidebar.items.isEmpty || sidebar.isSelectionMode
    }

    private var threadHeader: some View {
        HStack {
            Text(sidebar.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Spacer()
            if sidebar.isSelectionMode,
               let action = sidebar.bulkActions.first(where: { $0.kind == .clearSelection }) {
                Button(action.title) {
                    onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: action))
                }
                .font(.caption.weight(.medium))
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 56)
                .foregroundStyle(action.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
                .disabled(!action.isEnabled)
                .accessibilityIdentifier("quillcode-sidebar-\(action.kind.rawValue)")
            }
            QuillCodeSidebarSavedFilterBar(
                filters: sidebar.savedFilters,
                savedSearches: sidebar.customSavedSearches,
                createCommand: savedSearchCreateCommand,
                selectionCommand: selectionCommand,
                onCommand: onCommand
            )
        }
    }

    private var savedSearchCreateCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue }
    }

    private var selectionCommand: WorkspaceCommandSurface? {
        guard !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return nil }
        return QuillCodeSidebarCommandAdapter.workspaceCommand(for: action)
    }

}
