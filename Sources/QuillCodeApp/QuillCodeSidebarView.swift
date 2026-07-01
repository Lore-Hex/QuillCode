import SwiftUI

struct QuillCodeSidebarView: View {
    var projects: ProjectListSurface
    var sidebar: SidebarSurface
    var commands: [WorkspaceCommandSurface]
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void
    var onProjectAction: (ProjectItemActionSurface) -> Void
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuillCodeSidebarActionsView(commands: commands, onCommand: onCommand)
            if showsThreadHeader {
                Divider()
                threadHeader
                QuillCodeSidebarSavedFilterBar(
                    filters: sidebar.savedFilters,
                    onCommand: onCommand
                )
                if let createCommand = savedSearchCreateCommand {
                    QuillCodeSidebarSavedSearchBar(
                        savedSearches: sidebar.customSavedSearches,
                        createCommand: createCommand,
                        onCommand: onCommand
                    )
                }
                if sidebar.isSelectionMode {
                    QuillCodeSidebarBulkActionsView(
                        selectionLabel: sidebar.selectionLabel,
                        actions: sidebar.bulkActions.filter { $0.kind != .clearSelection },
                        onCommand: onCommand
                    )
                }
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
                onProjectAction: onProjectAction
            )
            Spacer(minLength: 0)
            QuillCodeSidebarUtilityActionsView(commands: commands, onCommand: onCommand)
        }
        .padding(14)
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
            if let action = sidebar.bulkActions.first(where: {
                sidebar.isSelectionMode ? $0.kind == .clearSelection : $0.kind == .select
            }) {
                Button(action.title) {
                    onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: action))
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 56)
                .foregroundStyle(action.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
                .disabled(!action.isEnabled)
                .accessibilityIdentifier("quillcode-sidebar-\(action.kind.rawValue)")
            }
        }
    }

    private var savedSearchCreateCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue }
    }

}
