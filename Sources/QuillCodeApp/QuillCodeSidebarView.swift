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
                if sidebar.isSelectionMode {
                    QuillCodeSidebarBulkActionsView(
                        selectionLabel: sidebar.selectionLabel,
                        actions: sidebar.bulkActions.filter { $0.kind != .clearSelection },
                        onCommand: onCommand
                    )
                }
            }
            threadList
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
                .foregroundStyle(action.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
                .disabled(!action.isEnabled)
            }
        }
    }

    @ViewBuilder
    private var threadList: some View {
        if sidebar.items.isEmpty {
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

private struct QuillCodeSidebarBulkActionsView: View {
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
                        .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
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

private struct QuillCodeSidebarThreadRowView: View {
    var item: SidebarItemSurface
    var isSelectionMode: Bool
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isSelectionMode {
                Button {
                    toggleSelection()
                } label: {
                    Image(systemName: item.isBulkSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.isBulkSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                        .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .accessibilityLabel(item.isBulkSelected ? "Deselect \(item.title)" : "Select \(item.title)")
            }
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
                .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
            }
            .buttonStyle(QuillCodePressableButtonStyle())

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
                    .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                    .foregroundStyle(QuillCodePalette.muted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuillCodePressableButtonStyle())
        }
        .padding(10)
        .background(item.isSelected ? QuillCodePalette.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggleSelection() {
        onCommand(QuillCodeSidebarCommandAdapter.toggleSelectionCommand(for: item))
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
        VStack(spacing: 8) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(
                        QuillCodeSidebarCommandPresentation.displayTitle(for: command),
                        systemImage: QuillCodeSidebarCommandPresentation.systemImage(for: command.id)
                    )
                        .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(command.id == "new-chat" ? QuillCodePalette.panel.opacity(0.74) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        HStack(spacing: 8) {
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
                    .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget)
                    .foregroundStyle(QuillCodePalette.muted)
                    .background(QuillCodePalette.panel.opacity(0.50))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget)
                        .foregroundStyle(settingsCommand.isEnabled ? QuillCodePalette.muted : QuillCodePalette.muted.opacity(0.45))
                        .background(QuillCodePalette.panel.opacity(0.50))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
