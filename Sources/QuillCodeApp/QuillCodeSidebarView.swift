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
            }
        }
    }

    private var savedSearchCreateCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue }
    }

}

private struct QuillCodeSidebarSavedSearchBar: View {
    var savedSearches: [SidebarSavedSearchSurface]
    var createCommand: WorkspaceCommandSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Text("Saved searches")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                Spacer()
                Button {
                    onCommand(createCommand)
                } label: {
                    Label("Save", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 64)
                .foregroundStyle(QuillCodePalette.blue)
            }

            if !savedSearches.isEmpty {
                VStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    ForEach(savedSearches) { savedSearch in
                        savedSearchRow(savedSearch)
                    }
                }
            }
        }
    }

    private func savedSearchRow(_ savedSearch: SidebarSavedSearchSurface) -> some View {
        HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            Button {
                onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: savedSearch))
            } label: {
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.small)
                    Text(savedSearch.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text("\(savedSearch.count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(savedSearch.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((savedSearch.isActive ? Color.white : QuillCodePalette.panel).opacity(0.28))
                        .clipShape(Capsule())
                }
                .quillCodeCapsuleButtonTarget(minWidth: 124, alignment: .leading)
                .foregroundStyle(savedSearch.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
                .background(savedSearch.isActive ? QuillCodePalette.blue : QuillCodePalette.panel.opacity(0.45))
                .clipShape(Capsule())
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityLabel(savedSearch.accessibilityLabel)
            .accessibilityAddTraits(savedSearch.isActive ? .isSelected : [])
            .help(savedSearch.query)

            savedSearchMoveButton(savedSearch, direction: .up, systemImage: "chevron.up")
            savedSearchMoveButton(savedSearch, direction: .down, systemImage: "chevron.down")
            Button {
                onCommand(QuillCodeSidebarCommandAdapter.deleteWorkspaceCommand(for: savedSearch))
            } label: {
                Image(systemName: "trash")
                    .imageScale(.small)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeIconButtonTarget()
            .foregroundStyle(QuillCodePalette.red)
            .accessibilityLabel("Delete saved search \(savedSearch.title)")
        }
    }

    private func savedSearchMoveButton(
        _ savedSearch: SidebarSavedSearchSurface,
        direction: SidebarSavedSearchMoveDirection,
        systemImage: String
    ) -> some View {
        let command = QuillCodeSidebarCommandAdapter.moveWorkspaceCommand(for: savedSearch, direction: direction)
        return Button {
            onCommand(command)
        } label: {
            Image(systemName: systemImage)
                .imageScale(.small)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeIconButtonTarget()
        .foregroundStyle(command.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
        .disabled(!command.isEnabled)
        .accessibilityLabel("Move saved search \(savedSearch.title) \(direction.rawValue)")
    }
}

private struct QuillCodeSidebarSavedFilterBar: View {
    var filters: [SidebarSavedFilterSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100), spacing: QuillCodeMetrics.denseControlClusterSpacing, alignment: .leading)],
            alignment: .leading,
            spacing: QuillCodeMetrics.denseControlClusterSpacing
        ) {
            ForEach(filters) { filter in
                Button {
                    onCommand(QuillCodeSidebarCommandAdapter.workspaceCommand(for: filter))
                } label: {
                    HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                        Text("\(filter.count)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(filter.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((filter.isActive ? Color.white : QuillCodePalette.panel).opacity(0.28))
                            .clipShape(Capsule())
                    }
                    .lineLimit(1)
                    .quillCodeCapsuleButtonTarget(minWidth: 66)
                    .foregroundStyle(filter.isActive ? QuillCodePalette.background : QuillCodePalette.muted)
                    .background(filter.isActive ? QuillCodePalette.blue : QuillCodePalette.panel.opacity(0.55))
                    .clipShape(Capsule())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .accessibilityLabel(filter.accessibilityLabel)
                .accessibilityAddTraits(filter.isActive ? .isSelected : [])
            }
        }
    }
}

private struct QuillCodeSidebarActionsView: View {
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    private var visibleCommands: [WorkspaceCommandSurface] {
        QuillCodeSidebarCommandPresentation.primaryCommandIDs.compactMap { id in
            commands.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(
                        QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                        systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
                    )
                        .quillCodeFullRowButtonTarget()
                        .padding(.horizontal, 10)
                        .background(command.id == "new-chat" ? QuillCodePalette.panel.opacity(0.74) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(!command.isEnabled)
            }
        }
    }
}

private struct QuillCodeSidebarUtilityActionsView: View {
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    private var visibleCommandGroups: [QuillCodeSidebarVisibleCommandGroup] {
        QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups(from: commands)
    }

    private var settingsCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == "settings" }
    }

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Menu {
                ForEach(visibleCommandGroups) { group in
                    Section(group.title) {
                        ForEach(group.commands) { command in
                            Button {
                                onCommand(command)
                            } label: {
                                Label(
                                    QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                                    systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
                                )
                            }
                            .disabled(!command.isEnabled)
                        }
                    }
                }
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
                    .font(.callout.weight(.semibold))
                    .quillCodeFullRowButtonTarget(alignment: .center, radius: 10)
                    .foregroundStyle(QuillCodePalette.muted)
                    .background(QuillCodePalette.panel.opacity(0.50))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .help("Tools")

            if let settingsCommand {
                Button {
                    onCommand(settingsCommand)
                } label: {
                    Label(
                        QuillCodeSidebarCommandPresentation.displayTitle(for: settingsCommand),
                        systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: settingsCommand.id)
                    )
                        .font(.callout.weight(.semibold))
                        .quillCodeFullRowButtonTarget(alignment: .center, radius: 10)
                        .foregroundStyle(settingsCommand.isEnabled ? QuillCodePalette.muted : QuillCodePalette.muted.opacity(0.45))
                        .background(QuillCodePalette.panel.opacity(0.50))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(!settingsCommand.isEnabled)
                .help(QuillCodeSidebarCommandPresentation.displayTitle(for: settingsCommand))
                .accessibilityLabel(QuillCodeSidebarCommandPresentation.displayTitle(for: settingsCommand))
            }
        }
        .padding(.top, 10)
    }
}
