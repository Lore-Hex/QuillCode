import SwiftUI
import QuillCodeCore

public struct QuillCodeWorkspaceView: View {
    public var surface: WorkspaceSurface
    @Binding public var draft: String
    @Binding public var terminalDraft: String
    @Binding public var browserAddressDraft: String
    @Binding public var isCommandPalettePresented: Bool
    @Binding public var isSettingsPresented: Bool
    public var onSend: () -> Void
    public var onRunTerminalCommand: () -> Void
    public var onOpenBrowserPreview: () -> Void
    public var onAddBrowserComment: (String) -> Void
    public var onAddProjectRequested: () -> Void
    public var onSelectThread: (UUID) -> Void
    public var onThreadAction: (SidebarItemActionSurface) -> Void
    public var onSelectProject: (UUID?) -> Void
    public var onSetMode: (AgentMode) -> Void
    public var onSetModel: (String) -> Void
    public var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    public var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    public var onAddReviewComment: (String, String) -> Void
    public var onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    public var onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    public var onCommand: (WorkspaceCommandSurface) -> Void

    @State private var isSearchPresented = false
    @State private var worktreeSheet: QuillCodeWorktreeSheet?
    @State private var searchQuery = ""
    @State private var commandQuery = ""
    @State private var settingsDraft = QuillCodeSettingsDraft()
    @State private var createWorktreeDraft = QuillCodeWorktreeCreateDraft()
    @State private var removeWorktreeDraft = QuillCodeWorktreeRemoveDraft()

    public init(
        surface: WorkspaceSurface,
        draft: Binding<String>,
        terminalDraft: Binding<String>,
        browserAddressDraft: Binding<String>,
        isCommandPalettePresented: Binding<Bool>,
        isSettingsPresented: Binding<Bool>,
        onSend: @escaping () -> Void,
        onRunTerminalCommand: @escaping () -> Void,
        onOpenBrowserPreview: @escaping () -> Void,
        onAddBrowserComment: @escaping (String) -> Void,
        onAddProjectRequested: @escaping () -> Void,
        onSelectThread: @escaping (UUID) -> Void,
        onThreadAction: @escaping (SidebarItemActionSurface) -> Void,
        onSelectProject: @escaping (UUID?) -> Void,
        onSetMode: @escaping (AgentMode) -> Void,
        onSetModel: @escaping (String) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onReviewAction: @escaping (WorkspaceReviewActionSurface) -> Void,
        onAddReviewComment: @escaping (String, String) -> Void,
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onRemoveWorktree: @escaping (WorkspaceWorktreeRemoveRequest) -> Void,
        onCommand: @escaping (WorkspaceCommandSurface) -> Void
    ) {
        self.surface = surface
        self._draft = draft
        self._terminalDraft = terminalDraft
        self._browserAddressDraft = browserAddressDraft
        self._isCommandPalettePresented = isCommandPalettePresented
        self._isSettingsPresented = isSettingsPresented
        self.onSend = onSend
        self.onRunTerminalCommand = onRunTerminalCommand
        self.onOpenBrowserPreview = onOpenBrowserPreview
        self.onAddBrowserComment = onAddBrowserComment
        self.onAddProjectRequested = onAddProjectRequested
        self.onSelectThread = onSelectThread
        self.onThreadAction = onThreadAction
        self.onSelectProject = onSelectProject
        self.onSetMode = onSetMode
        self.onSetModel = onSetModel
        self.onSaveSettings = onSaveSettings
        self.onReviewAction = onReviewAction
        self.onAddReviewComment = onAddReviewComment
        self.onCreateWorktree = onCreateWorktree
        self.onRemoveWorktree = onRemoveWorktree
        self.onCommand = onCommand
    }

    public var body: some View {
        VStack(spacing: 0) {
            QuillCodeTopBarView(
                topBar: surface.topBar,
                commands: surface.commands,
                onSetMode: onSetMode,
                onSetModel: onSetModel,
                onCommand: handleCommand
            )
            Divider()
            HStack(spacing: 0) {
                QuillCodeSidebarView(
                    projects: surface.projects,
                    sidebar: surface.sidebar,
                    commands: surface.commands,
                    onSelectProject: onSelectProject,
                    onAddProjectRequested: onAddProjectRequested,
                    onSelectThread: onSelectThread,
                    onThreadAction: onThreadAction,
                    onCommand: handleCommand
                )
                    .frame(width: 280)
                Divider()
                VStack(spacing: 0) {
                    QuillCodeTranscriptView(
                        transcript: surface.transcript,
                        contextBanner: surface.contextBanner,
                        review: surface.review,
                        onContextCommand: handleCommand,
                        onReviewAction: onReviewAction,
                        onAddReviewComment: onAddReviewComment
                    )
                    if surface.browser.isVisible {
                        Divider()
                        QuillCodeBrowserPaneView(
                            browser: surface.browser,
                            addressDraft: $browserAddressDraft,
                            onOpen: onOpenBrowserPreview,
                            onAddComment: onAddBrowserComment
                        )
                    }
                    if surface.terminal.isVisible {
                        Divider()
                        QuillCodeTerminalPaneView(
                            terminal: surface.terminal,
                            draft: $terminalDraft,
                            onRun: onRunTerminalCommand
                        )
                    }
                    Divider()
                    QuillCodeComposerView(
                        composer: surface.composer,
                        draft: $draft,
                        onSend: onSend
                    )
                }
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .sheet(isPresented: $isSettingsPresented) {
            QuillCodeSettingsView(
                settings: surface.settings,
                draft: $settingsDraft,
                onCancel: {
                    isSettingsPresented = false
                },
                onSave: {
                    onSaveSettings(settingsDraft.update)
                    isSettingsPresented = false
                }
            )
        }
        .onChange(of: isSettingsPresented) { _, isPresented in
            if isPresented {
                settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            QuillCodeSearchView(
                sidebar: surface.sidebar,
                query: $searchQuery,
                onSelectThread: { threadID in
                    onSelectThread(threadID)
                    isSearchPresented = false
                },
                onClose: {
                    isSearchPresented = false
                }
            )
        }
        .sheet(isPresented: $isCommandPalettePresented) {
            QuillCodeCommandPaletteView(
                commands: surface.commands.filter { $0.id != "command-palette" },
                query: $commandQuery,
                onSelectCommand: { command in
                    isCommandPalettePresented = false
                    handleCommand(command)
                },
                onClose: {
                    isCommandPalettePresented = false
                }
            )
        }
        .sheet(item: $worktreeSheet) { sheet in
            switch sheet {
            case .create:
                QuillCodeWorktreeCreateView(
                    draft: $createWorktreeDraft,
                    onCancel: {
                        worktreeSheet = nil
                    },
                    onCreate: {
                        onCreateWorktree(createWorktreeDraft.request)
                        worktreeSheet = nil
                    }
                )
            case .remove:
                QuillCodeWorktreeRemoveView(
                    draft: $removeWorktreeDraft,
                    onCancel: {
                        worktreeSheet = nil
                    },
                    onRemove: {
                        onRemoveWorktree(removeWorktreeDraft.request)
                        worktreeSheet = nil
                    }
                )
            }
        }
    }

    private func handleCommand(_ command: WorkspaceCommandSurface) {
        if command.id == "settings" {
            settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
            isSettingsPresented = true
        } else if command.id == "search" {
            searchQuery = ""
            isSearchPresented = true
        } else if command.id == "add-project" {
            onAddProjectRequested()
        } else if command.id == "command-palette" {
            commandQuery = ""
            isCommandPalettePresented = true
        } else if command.id == "git-worktree-create" {
            createWorktreeDraft = QuillCodeWorktreeCreateDraft()
            worktreeSheet = .create
        } else if command.id == "git-worktree-remove" {
            removeWorktreeDraft = QuillCodeWorktreeRemoveDraft()
            worktreeSheet = .remove
        } else {
            onCommand(command)
        }
    }
}

private enum QuillCodeWorktreeSheet: String, Identifiable {
    case create
    case remove

    var id: String { rawValue }
}

private struct QuillCodeCommandPaletteView: View {
    var commands: [WorkspaceCommandSurface]
    @Binding var query: String
    var onSelectCommand: (WorkspaceCommandSurface) -> Void
    var onClose: () -> Void

    @State private var selectedCommandID: String?

    private var results: [WorkspaceCommandSurface] {
        WorkspaceCommandPalette.rankedCommands(commands, matching: query)
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPalette.groupedCommands(commands, matching: query)
    }

    private var enabledResults: [WorkspaceCommandSurface] {
        results.filter(\.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command palette")
                        .font(.title2.weight(.semibold))
                    Text("Run QuillCode workspace actions from one place.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            TextField("Search commands", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(selectHighlightedCommand)

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.title2)
                        .foregroundStyle(QuillCodePalette.muted)
                    Text("No matching commands")
                        .font(.headline)
                    Text("Try a command name or shortcut.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .textCase(.uppercase)
                                ForEach(group.commands) { command in
                                    commandButton(command)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
        .onAppear(perform: ensureSelection)
        .onChange(of: query) { _, _ in
            ensureSelection()
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                moveSelection(by: -1)
            case .down:
                moveSelection(by: 1)
            default:
                break
            }
        }
    }

    private func commandButton(_ command: WorkspaceCommandSurface) -> some View {
        Button {
            selectedCommandID = command.id
            onSelectCommand(command)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage(for: command.id))
                    .foregroundStyle(command.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(command.title)
                        .font(.callout.weight(.semibold))
                    if !command.keywords.isEmpty {
                        Text(command.keywords.prefix(3).joined(separator: " - "))
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            .padding(12)
            .background(command.id == selectedCommandID ? QuillCodePalette.selection : QuillCodePalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(command.id == selectedCommandID ? QuillCodePalette.blue.opacity(0.6) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!command.isEnabled)
    }

    private func ensureSelection() {
        if let selectedCommandID, enabledResults.contains(where: { $0.id == selectedCommandID }) {
            return
        }
        selectedCommandID = enabledResults.first?.id
    }

    private func moveSelection(by delta: Int) {
        guard !enabledResults.isEmpty else {
            selectedCommandID = nil
            return
        }
        let currentIndex = selectedCommandID.flatMap { id in
            enabledResults.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = (currentIndex + delta + enabledResults.count) % enabledResults.count
        selectedCommandID = enabledResults[nextIndex].id
    }

    private func selectHighlightedCommand() {
        guard let command = enabledResults.first(where: { $0.id == selectedCommandID }) ?? enabledResults.first else {
            return
        }
        onSelectCommand(command)
    }

    private func systemImage(for commandID: String) -> String {
        switch commandID {
        case "new-chat":
            return "square.and.pencil"
        case "search":
            return "magnifyingglass"
        case "add-project":
            return "folder.badge.plus"
        case "toggle-terminal":
            return "terminal"
        case "toggle-browser":
            return "globe"
        case "git-pr-create":
            return "arrow.up.doc"
        case "git-worktree-list":
            return "point.3.connected.trianglepath.dotted"
        case "git-worktree-create":
            return "plus.rectangle.on.folder"
        case "git-worktree-remove":
            return "minus.rectangle"
        case "settings":
            return "gearshape"
        case "computer-use-setup":
            return "display"
        case "stop-all":
            return "stop.circle"
        default:
            if commandID.hasPrefix("local-env:") {
                return "hammer"
            }
            return "command"
        }
    }
}

private struct QuillCodeSearchView: View {
    var sidebar: SidebarSurface
    @Binding var query: String
    var onSelectThread: (UUID) -> Void
    var onClose: () -> Void

    private var results: [SidebarItemSurface] {
        sidebar.filteredItems(matching: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search chats")
                        .font(.title2.weight(.semibold))
                    Text("Find a thread by title, model, pinned state, or transcript text.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            TextField("Search chats", text: $query)
                .textFieldStyle(.roundedBorder)

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(QuillCodePalette.muted)
                    Text("No matching chats")
                        .font(.headline)
                    Text("Try a thread title, selected model, pinned, or prior message text.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { item in
                            Button {
                                onSelectThread(item.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isPinned ? "pin.fill" : "text.bubble")
                                        .foregroundStyle(item.isSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text(item.subtitle + (item.isPinned ? " - pinned" : ""))
                                            .font(.caption)
                                            .foregroundStyle(QuillCodePalette.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if item.isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(QuillCodePalette.blue)
                                    }
                                }
                                .padding(12)
                                .background(item.isSelected ? QuillCodePalette.selection : QuillCodePalette.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(QuillCodePalette.background)
    }
}

private struct QuillCodeTopBarView: View {
    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(QuillCodePalette.blue.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(topBar.primaryTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(topBar.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(topBar.modelCategories) { category in
                    Section(category.category) {
                        ForEach(category.models) { option in
                            Button {
                                onSetModel(option.id)
                            } label: {
                                HStack {
                                    Text("\(option.provider)/\(option.displayName)")
                                    if option.isSelected {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                QuillCodePill(text: topBar.modelLabel, systemImage: "cpu")
            }
            .buttonStyle(.borderless)
            Menu {
                ForEach(AgentMode.allCases, id: \.rawValue) { mode in
                    Button(mode.title) {
                        onSetMode(mode)
                    }
                }
            } label: {
                QuillCodePill(text: topBar.modeLabel, systemImage: "shield")
            }
            .buttonStyle(.borderless)
            QuillCodePill(text: topBar.agentStatus, systemImage: "waveform.path")
            QuillCodePill(text: topBar.instructionLabel, systemImage: topBar.instructionSources.isEmpty ? "doc" : "doc.text.magnifyingglass")
                .help(topBar.instructionSources.isEmpty ? topBar.instructionLabel : topBar.instructionSources.joined(separator: "\n"))
            Menu {
                ForEach(commands) { command in
                    Button(command.title) {
                        onCommand(command)
                    }
                    .disabled(!command.isEnabled)
                    if let shortcut = command.shortcut {
                        Text(shortcut)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .background(QuillCodePalette.panel)
    }
}

private struct QuillCodeSidebarView: View {
    var projects: ProjectListSurface
    var sidebar: SidebarSurface
    var commands: [WorkspaceCommandSurface]
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuillCodeSidebarActionsView(commands: commands, onCommand: onCommand)
            Divider()
            QuillCodeProjectListView(
                projects: projects,
                onSelectProject: onSelectProject,
                onAddProjectRequested: onAddProjectRequested
            )
            Divider()
            Text(sidebar.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
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
                                onSelectThread: onSelectThread,
                                onThreadAction: onThreadAction
                            )
                        }
                        if !sidebar.recentItems.isEmpty {
                            QuillCodeSidebarThreadSectionView(
                                title: "Recent",
                                items: sidebar.recentItems,
                                onSelectThread: onSelectThread,
                                onThreadAction: onThreadAction
                            )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(QuillCodePalette.sidebar)
    }
}

private struct QuillCodeSidebarThreadSectionView: View {
    var title: String
    var items: [SidebarItemSurface]
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .padding(.top, 4)
            ForEach(items) { item in
                QuillCodeSidebarThreadRowView(
                    item: item,
                    onSelectThread: onSelectThread,
                    onThreadAction: onThreadAction
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuillCodeSidebarThreadRowView: View {
    var item: SidebarItemSurface
    var onSelectThread: (UUID) -> Void
    var onThreadAction: (SidebarItemActionSurface) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelectThread(item.id)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Menu {
                ForEach(item.actions) { action in
                    Button(action.kind.title) {
                        onThreadAction(action)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(item.isSelected ? QuillCodePalette.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct QuillCodeSidebarActionsView: View {
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    private var visibleCommands: [WorkspaceCommandSurface] {
        commands.filter { ["new-chat", "search", "toggle-browser", "toggle-terminal"].contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(visibleCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    Label(command.title, systemImage: systemImage(for: command.id))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(QuillCodePalette.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!command.isEnabled)
            }
        }
    }

    private func systemImage(for commandID: String) -> String {
        switch commandID {
        case "new-chat":
            return "square.and.pencil"
        case "search":
            return "magnifyingglass"
        case "toggle-terminal":
            return "terminal"
        case "toggle-browser":
            return "globe"
        default:
            return "circle"
        }
    }
}

private struct QuillCodeWorktreeCreateView: View {
    @Binding var draft: QuillCodeWorktreeCreateDraft
    var onCancel: () -> Void
    var onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Worktree")
                        .font(.title2.weight(.semibold))
                    Text("Create a sibling git worktree for this project.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.title2)
                    .foregroundStyle(QuillCodePalette.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Worktree folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("quillcode-feature", text: $draft.path)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("New branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("feature/quillcode", text: $draft.branch)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Base ref")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("main", text: $draft.base)
                    .textFieldStyle(.roundedBorder)
                Text("Leave branch or base blank to use git defaults.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canCreate)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(QuillCodePalette.background)
    }
}

private struct QuillCodeWorktreeRemoveView: View {
    @Binding var draft: QuillCodeWorktreeRemoveDraft
    var onCancel: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remove Worktree")
                        .font(.title2.weight(.semibold))
                    Text("Remove an existing registered git worktree.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Image(systemName: "minus.rectangle")
                    .font(.title2)
                    .foregroundStyle(QuillCodePalette.yellow)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Worktree folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("quillcode-feature", text: $draft.path)
                    .textFieldStyle(.roundedBorder)
                Text("Removal is limited to worktrees registered by git.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }

            Toggle("Force removal", isOn: $draft.force)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Remove", action: onRemove)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canRemove)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(QuillCodePalette.background)
    }
}

private struct QuillCodeProjectListView: View {
    var projects: ProjectListSurface
    var onSelectProject: (UUID?) -> Void
    var onAddProjectRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(projects.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
                Button(action: onAddProjectRequested) {
                    Image(systemName: "plus.circle")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(QuillCodePalette.muted)
                .help("Open project")
                Button {
                    onSelectProject(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(QuillCodePalette.muted)
                .help("Clear project")
            }
            if projects.items.isEmpty {
                Text(projects.emptyTitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            } else {
                ForEach(projects.items) { project in
                    Button {
                        onSelectProject(project.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(project.path)
                                .font(.caption)
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(project.isSelected ? QuillCodePalette.selection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct QuillCodeTranscriptView: View {
    var transcript: TranscriptSurface
    var contextBanner: ContextBannerSurface?
    var review: WorkspaceReviewSurface
    var onContextCommand: (WorkspaceCommandSurface) -> Void
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if transcript.messages.isEmpty && transcript.toolCards.isEmpty && !review.isVisible && contextBanner == nil {
                    VStack(spacing: 8) {
                        Text(transcript.emptyTitle)
                            .font(.title3.weight(.semibold))
                        Text(transcript.emptySubtitle)
                            .font(.callout)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                    .padding(.top, 180)
                } else {
                    if let contextBanner {
                        QuillCodeContextBannerView(
                            banner: contextBanner,
                            onCommand: onContextCommand
                        )
                    }
                    if review.isVisible {
                        QuillCodeReviewPaneView(
                            review: review,
                            onReviewAction: onReviewAction,
                            onAddReviewComment: onAddReviewComment
                        )
                    }
                    ForEach(transcript.messages) { message in
                        QuillCodeMessageBubble(message: message)
                    }
                    ForEach(transcript.toolCards) { card in
                        QuillCodeToolCardView(card: card)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .background(QuillCodePalette.background)
    }
}

private struct QuillCodeContextBannerView: View {
    var banner: ContextBannerSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.bubble.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(QuillCodePalette.yellow)
                .frame(width: 34, height: 34)
                .background(QuillCodePalette.yellow.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(banner.title)
                        .font(.headline)
                    Text("\(banner.usedPercent)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(QuillCodePalette.yellow.opacity(0.14))
                        .clipShape(Capsule())
                }
                Text(banner.subtitle)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
                HStack(spacing: 8) {
                    Button(banner.newThreadCommand.title) {
                        onCommand(banner.newThreadCommand)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(banner.forkCommand.title) {
                        onCommand(banner.forkCommand)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!banner.forkCommand.isEnabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuillCodePalette.yellow.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuillCodeTerminalPaneView: View {
    var terminal: TerminalSurface
    @Binding var draft: String
    var onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .foregroundStyle(QuillCodePalette.blue)
                Text("Terminal")
                    .font(.headline)
                Text(terminal.cwdLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                Spacer()
                if terminal.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if terminal.entries.isEmpty {
                        Text(terminal.emptyTitle)
                            .font(.callout)
                            .foregroundStyle(QuillCodePalette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(terminal.entries) { entry in
                            QuillCodeTerminalEntryView(entry: entry)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.body.monospaced())
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("Run command", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onRun)
                    .disabled(terminal.isRunning)
                Button("Run", action: onRun)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || terminal.isRunning)
            }
        }
        .padding(14)
        .frame(height: 220)
        .background(QuillCodePalette.panel)
    }
}

private struct QuillCodeBrowserPaneView: View {
    var browser: BrowserSurface
    @Binding var addressDraft: String
    var onOpen: () -> Void
    var onAddComment: (String) -> Void

    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(QuillCodePalette.blue)
                Text("Browser")
                    .font(.headline)
                Text(browser.statusLabel)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("localhost:3000, docs/page.html, or https://example.com", text: $addressDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onOpen)
                Button("Open", action: onOpen)
                    .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let currentURL = browser.currentURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text(browser.title)
                        .font(.callout.weight(.semibold))
                    Text(currentURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                    Text("Ready for page inspection.")
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillCodePalette.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(browser.emptyTitle)
                        .font(.callout.weight(.semibold))
                    Text(browser.emptySubtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                TextField("Add browser comment", text: $commentDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(browser.currentURL == nil)
                    .onSubmit(addComment)
                Button("Comment", action: addComment)
                    .disabled(browser.currentURL == nil || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !browser.comments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(browser.comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.text)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(comment.url)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(width: 220, alignment: .leading)
                            .background(QuillCodePalette.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(height: 260)
        .background(QuillCodePalette.panel)
    }

    private func addComment() {
        let comment = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return }
        onAddComment(comment)
        commentDraft = ""
    }
}

private struct QuillCodeTerminalEntryView: View {
    var entry: TerminalCommandSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("$ \(entry.command)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                Spacer()
                Text("\(entry.statusLabel) · \(entry.exitCodeLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(entry.isSuccess ? QuillCodePalette.green : QuillCodePalette.red)
            }
            if !entry.stdout.isEmpty {
                Text(entry.stdout)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !entry.stderr.isEmpty {
                Text(entry.stderr)
                    .font(.caption.monospaced())
                    .foregroundStyle(QuillCodePalette.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(QuillCodePalette.blue)
                    .frame(width: 34, height: 34)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(review.title)
                        .font(.headline)
                    Text(review.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text("\(review.totalHunks) hunk\(review.totalHunks == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .foregroundStyle(QuillCodePalette.blue)
                    .clipShape(Capsule())
            }

            VStack(spacing: 0) {
                ForEach(review.files) { file in
                    QuillCodeReviewFileRowView(
                        file: file,
                        onReviewAction: onReviewAction,
                        onAddReviewComment: onAddReviewComment
                    )
                    if file.id != review.files.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QuillCodePalette.blue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuillCodeReviewFileRowView: View {
    var file: WorkspaceReviewFileSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, String) -> Void

    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: file.isBinary ? "photo" : "doc.plaintext")
                    .foregroundStyle(QuillCodePalette.muted)
                    .frame(width: 20)
                Text(file.path)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(file.changeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
                HStack(spacing: 6) {
                    ForEach(file.actions) { action in
                        QuillCodeReviewActionButton(action: action, path: file.path, onReviewAction: onReviewAction)
                    }
                }
            }

            ForEach(file.hunkItems) { hunk in
                HStack(spacing: 8) {
                    Text(hunk.header)
                        .font(.caption.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                    Text(hunk.changeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(QuillCodePalette.muted)
                    Spacer()
                    ForEach(hunk.actions) { action in
                        QuillCodeReviewActionButton(action: action, path: hunk.path, onReviewAction: onReviewAction)
                    }
                }
                .padding(.leading, 30)
            }

            if !file.comments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(file.comments) { comment in
                        Label(comment.text, systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.text)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.leading, 30)
            }

            HStack(spacing: 8) {
                TextField("Add review note", text: $commentDraft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(QuillCodePalette.background.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button {
                    let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAddReviewComment(file.path, text)
                    commentDraft = ""
                } label: {
                    Label("Add review note", systemImage: "plus.bubble")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add review note to \(file.path)")
            }
            .padding(.leading, 30)
        }
        .padding(.vertical, 8)
    }
}

private struct QuillCodeReviewActionButton: View {
    var action: WorkspaceReviewActionSurface
    var path: String
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void

    var body: some View {
        Button {
            onReviewAction(action)
        } label: {
            Label(action.kind.title, systemImage: action.kind.systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("\(action.kind.title) \(path)")
        .foregroundStyle(action.kind == .restore || action.kind == .restoreHunk ? QuillCodePalette.yellow : QuillCodePalette.blue)
    }
}

private struct QuillCodeMessageBubble: View {
    var message: MessageSurface

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(message.accessibilityLabel)
            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(LinearGradient(colors: [QuillCodePalette.blue, QuillCodePalette.coral], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(QuillCodePalette.panel)
    }
}

private struct QuillCodeToolCardView: View {
    var card: ToolCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                    Text(card.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text(card.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.16))
                    .clipShape(Capsule())
            }
            if card.isExpanded || card.status == .failed || card.status == .done {
                if let inputJSON = card.inputJSON {
                    QuillCodeCodeBlock(title: "Input", text: inputJSON)
                }
                if let outputJSON = card.outputJSON {
                    QuillCodeCodeBlock(title: "Output", text: outputJSON)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 760, alignment: .leading)
        .background(QuillCodePalette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        switch card.status {
        case .queued, .running:
            return QuillCodePalette.blue
        case .done:
            return QuillCodePalette.green
        case .failed:
            return QuillCodePalette.red
        case .review:
            return QuillCodePalette.yellow
        }
    }

    private var iconName: String {
        switch card.status {
        case .queued, .running:
            return "waveform.path"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .review:
            return "shield.lefthalf.filled"
        }
    }
}

private struct QuillCodeCodeBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

private struct QuillCodeComposerView: View {
    var composer: ComposerSurface
    @Binding var draft: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(composer.placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(12)
                .background(Color.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(composer.isSending)
                .onSubmit(onSend)
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || composer.isSending)
        }
        .padding(14)
        .background(QuillCodePalette.panel)
    }
}

private struct QuillCodeSettingsView: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text(settings.loginStatusLabel)
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text(settings.apiKeyStatusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.16))
                    .foregroundStyle(settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow)
                    .clipShape(Capsule())
            }

            Picker("Authentication", selection: $draft.authMode) {
                Text("TrustedRouter login").tag(TrustedRouterAuthMode.oauth)
                Text("Developer override").tag(TrustedRouterAuthMode.developerOverride)
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.authMode) { _, mode in
                draft.developerOverrideEnabled = mode == .developerOverride
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TrustedRouter API base URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextField("https://api.quillrouter.com/v1", text: $draft.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
            }

            if draft.authMode == .oauth {
                Text("OAuth browser login will use the TrustedRouter account flow. Developer keys stay hidden unless you switch modes.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Replace API key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    SecureField(settings.hasStoredAPIKey ? "Leave blank to keep saved key" : "Paste TrustedRouter key", text: $draft.replacementAPIKey)
                        .textFieldStyle(.roundedBorder)
                    if draft.shouldClearAPIKey {
                        Text("Saved key will be cleared when you save.")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.yellow)
                    }
                    Button("Clear API key") {
                        draft.replacementAPIKey = ""
                        draft.shouldClearAPIKey = true
                    }
                    .disabled(!settings.hasStoredAPIKey)
                    .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct QuillCodeSettingsDraft: Equatable {
    var apiBaseURL: String = ""
    var authMode: TrustedRouterAuthMode = .oauth
    var developerOverrideEnabled: Bool = false
    var replacementAPIKey: String = ""
    var shouldClearAPIKey: Bool = false

    init() {}

    init(settings: WorkspaceSettingsSurface) {
        self.apiBaseURL = settings.apiBaseURL
        self.authMode = settings.authMode
        self.developerOverrideEnabled = settings.developerOverrideEnabled
    }

    var canSave: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var update: WorkspaceSettingsUpdate {
        WorkspaceSettingsUpdate(
            apiBaseURL: apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            authMode: authMode,
            developerOverrideEnabled: developerOverrideEnabled,
            replacementAPIKey: replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            shouldClearAPIKey: shouldClearAPIKey
        )
    }
}

private struct QuillCodeWorktreeCreateDraft: Equatable {
    var path = ""
    var branch = ""
    var base = ""

    var canCreate: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeCreateRequest {
        WorkspaceWorktreeCreateRequest(
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            base: base.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct QuillCodeWorktreeRemoveDraft: Equatable {
    var path = ""
    var force = false

    var canRemove: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: WorkspaceWorktreeRemoveRequest {
        WorkspaceWorktreeRemoveRequest(
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            force: force
        )
    }
}

private struct QuillCodePill: View {
    var text: String
    var systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(QuillCodePalette.blue.opacity(0.14))
            .foregroundStyle(QuillCodePalette.blue)
            .clipShape(Capsule())
    }
}

private extension AgentMode {
    var title: String {
        switch self {
        case .readOnly:
            return "Read-only"
        case .review:
            return "Review"
        case .auto:
            return "Auto"
        }
    }
}

private enum QuillCodePalette {
    static let background = Color(red: 0.03, green: 0.06, blue: 0.08)
    static let sidebar = Color(red: 0.07, green: 0.10, blue: 0.12)
    static let panel = Color(red: 0.10, green: 0.15, blue: 0.18)
    static let selection = Color.white.opacity(0.08)
    static let text = Color(red: 0.93, green: 0.97, blue: 0.98)
    static let muted = Color(red: 0.62, green: 0.69, blue: 0.72)
    static let blue = Color(red: 0.25, green: 0.72, blue: 0.91)
    static let green = Color(red: 0.32, green: 0.82, blue: 0.45)
    static let red = Color(red: 1.0, green: 0.36, blue: 0.32)
    static let yellow = Color(red: 0.97, green: 0.72, blue: 0.31)
    static let coral = Color(red: 0.82, green: 0.42, blue: 0.37)
}
