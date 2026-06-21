import SwiftUI
import QuillCodeCore

public struct QuillCodeWorkspaceView: View {
    public var surface: WorkspaceSurface
    @Binding public var draft: String
    @Binding public var terminalDraft: String
    @Binding public var browserAddressDraft: String
    @Binding public var isCommandPalettePresented: Bool
    @Binding public var isSettingsPresented: Bool
    @Binding public var isKeyboardShortcutsPresented: Bool
    public var copiedTranscriptItemID: String?
    public var onSend: () -> Void
    public var onRunTerminalCommand: () -> Void
    public var onOpenBrowserPreview: () -> Void
    public var onAddBrowserComment: (String) -> Void
    public var onAddProjectRequested: () -> Void
    public var onSelectThread: (UUID) -> Void
    public var onThreadAction: (SidebarItemActionSurface) -> Void
    public var onRenameThread: (UUID, String) -> Void
    public var onSelectProject: (UUID?) -> Void
    public var onProjectAction: (ProjectItemActionSurface) -> Void
    public var onRenameProject: (UUID, String) -> Void
    public var onSetMode: (AgentMode) -> Void
    public var onSetModel: (String) -> Void
    public var onToggleModelFavorite: (String) -> Void
    public var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    public var onStartTrustedRouterSignIn: () -> Void
    public var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    public var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    public var onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    public var onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    public var onCopyTranscriptItem: (String, String) -> Void
    public var onMessageFeedback: (UUID, MessageFeedbackValue) -> Void
    public var onCommand: (WorkspaceCommandSurface) -> Void

    @State private var isSearchPresented = false
    @State private var isFindPresented = false
    @State private var isModelPickerPresented = false
    @State private var worktreeSheet: QuillCodeWorktreeSheet?
    @State private var searchQuery = ""
    @State private var findQuery = ""
    @State private var activeFindIndex = 0
    @State private var commandQuery = ""
    @State private var settingsDraft = QuillCodeSettingsDraft()
    @State private var createWorktreeDraft = QuillCodeWorktreeCreateDraft()
    @State private var removeWorktreeDraft = QuillCodeWorktreeRemoveDraft()
    @State private var renameThreadDraft: QuillCodeThreadRenameDraft?
    @State private var renameProjectDraft: QuillCodeProjectRenameDraft?
    @FocusState private var isComposerFocused: Bool

    public init(
        surface: WorkspaceSurface,
        draft: Binding<String>,
        terminalDraft: Binding<String>,
        browserAddressDraft: Binding<String>,
        isCommandPalettePresented: Binding<Bool>,
        isSettingsPresented: Binding<Bool>,
        isKeyboardShortcutsPresented: Binding<Bool>,
        copiedTranscriptItemID: String? = nil,
        onSend: @escaping () -> Void,
        onRunTerminalCommand: @escaping () -> Void,
        onOpenBrowserPreview: @escaping () -> Void,
        onAddBrowserComment: @escaping (String) -> Void,
        onAddProjectRequested: @escaping () -> Void,
        onSelectThread: @escaping (UUID) -> Void,
        onThreadAction: @escaping (SidebarItemActionSurface) -> Void,
        onRenameThread: @escaping (UUID, String) -> Void,
        onSelectProject: @escaping (UUID?) -> Void,
        onProjectAction: @escaping (ProjectItemActionSurface) -> Void,
        onRenameProject: @escaping (UUID, String) -> Void,
        onSetMode: @escaping (AgentMode) -> Void,
        onSetModel: @escaping (String) -> Void,
        onToggleModelFavorite: @escaping (String) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onStartTrustedRouterSignIn: @escaping () -> Void,
        onReviewAction: @escaping (WorkspaceReviewActionSurface) -> Void,
        onAddReviewComment: @escaping (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void,
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onRemoveWorktree: @escaping (WorkspaceWorktreeRemoveRequest) -> Void,
        onCopyTranscriptItem: @escaping (String, String) -> Void = { _, _ in },
        onMessageFeedback: @escaping (UUID, MessageFeedbackValue) -> Void = { _, _ in },
        onCommand: @escaping (WorkspaceCommandSurface) -> Void
    ) {
        self.surface = surface
        self._draft = draft
        self._terminalDraft = terminalDraft
        self._browserAddressDraft = browserAddressDraft
        self._isCommandPalettePresented = isCommandPalettePresented
        self._isSettingsPresented = isSettingsPresented
        self._isKeyboardShortcutsPresented = isKeyboardShortcutsPresented
        self.copiedTranscriptItemID = copiedTranscriptItemID
        self.onSend = onSend
        self.onRunTerminalCommand = onRunTerminalCommand
        self.onOpenBrowserPreview = onOpenBrowserPreview
        self.onAddBrowserComment = onAddBrowserComment
        self.onAddProjectRequested = onAddProjectRequested
        self.onSelectThread = onSelectThread
        self.onThreadAction = onThreadAction
        self.onRenameThread = onRenameThread
        self.onSelectProject = onSelectProject
        self.onProjectAction = onProjectAction
        self.onRenameProject = onRenameProject
        self.onSetMode = onSetMode
        self.onSetModel = onSetModel
        self.onToggleModelFavorite = onToggleModelFavorite
        self.onSaveSettings = onSaveSettings
        self.onStartTrustedRouterSignIn = onStartTrustedRouterSignIn
        self.onReviewAction = onReviewAction
        self.onAddReviewComment = onAddReviewComment
        self.onCreateWorktree = onCreateWorktree
        self.onRemoveWorktree = onRemoveWorktree
        self.onCopyTranscriptItem = onCopyTranscriptItem
        self.onMessageFeedback = onMessageFeedback
        self.onCommand = onCommand
    }

    public var body: some View {
        VStack(spacing: 0) {
            QuillCodeTopBarView(
                topBar: surface.topBar,
                commands: surface.commands,
                isModelPickerPresented: $isModelPickerPresented,
                onSetMode: onSetMode,
                onSetModel: onSetModel,
                onToggleModelFavorite: onToggleModelFavorite,
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
                    onProjectAction: handleProjectAction,
                    onSelectThread: onSelectThread,
                    onThreadAction: handleThreadAction,
                    onCommand: handleCommand
                )
                    .frame(width: 280)
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        QuillCodeTranscriptView(
                            transcript: surface.transcript,
                            contextBanner: surface.contextBanner,
                            runtimeIssue: surface.runtimeIssue,
                            review: surface.review,
                            retryLastTurnCommand: surface.commands.first { $0.id == "retry-last-turn" && $0.isEnabled },
                            isFindPresented: $isFindPresented,
                            findQuery: $findQuery,
                            activeFindIndex: $activeFindIndex,
                            copiedTranscriptItemID: copiedTranscriptItemID,
                            onContextCommand: handleCommand,
                            onRuntimeIssueAction: runtimeIssueAction(for: surface.runtimeIssue),
                            onReviewAction: onReviewAction,
                            onAddReviewComment: onAddReviewComment,
                            onCopyTranscriptItem: onCopyTranscriptItem,
                            onUseMessageAsDraft: useMessageAsDraft,
                            onMessageFeedback: onMessageFeedback
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
                        if surface.extensions.isVisible {
                            Divider()
                            QuillCodeExtensionsPaneView(
                                extensions: surface.extensions,
                                onCommand: handleCommand
                            )
                        }
                        if surface.memories.isVisible {
                            Divider()
                            QuillCodeMemoriesPaneView(memories: surface.memories) { commandID in
                                if let command = surface.commands.first(where: { $0.id == commandID }) {
                                    handleCommand(command)
                                } else if commandID.hasPrefix("memory-delete:") {
                                    handleCommand(WorkspaceCommandSurface(
                                        id: commandID,
                                        title: "Forget memory",
                                        category: WorkspaceCommandPalette.memoriesCategory,
                                        keywords: ["memory", "forget", "delete"]
                                    ))
                                }
                            }
                        }
                        if surface.terminal.isVisible {
                            Divider()
                            QuillCodeTerminalPaneView(
                                terminal: surface.terminal,
                                draft: $terminalDraft,
                                onRun: onRunTerminalCommand,
                                onStop: stopActiveRun
                            )
                        }
                        Divider()
                        QuillCodeComposerView(
                            composer: surface.composer,
                            draft: $draft,
                            isFocused: $isComposerFocused,
                            onSend: onSend,
                            onStop: stopActiveRun
                        )
                    }
                    if surface.activity.isVisible {
                        Divider()
                        QuillCodeActivityPaneView(activity: surface.activity)
                            .frame(width: 320)
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
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
                },
                onStartTrustedRouterSignIn: {
                    onStartTrustedRouterSignIn()
                },
                onCommand: handleCommand
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
        .sheet(isPresented: $isKeyboardShortcutsPresented) {
            QuillCodeKeyboardShortcutsView(
                commands: surface.commands,
                onClose: {
                    isKeyboardShortcutsPresented = false
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
        .sheet(item: $renameThreadDraft) { draft in
            QuillCodeThreadRenameView(
                draft: draft,
                onCancel: {
                    renameThreadDraft = nil
                },
                onSave: { threadID, title in
                    onRenameThread(threadID, title)
                    renameThreadDraft = nil
                }
            )
        }
        .sheet(item: $renameProjectDraft) { draft in
            QuillCodeProjectRenameView(
                draft: draft,
                onCancel: {
                    renameProjectDraft = nil
                },
                onSave: { projectID, name in
                    onRenameProject(projectID, name)
                    renameProjectDraft = nil
                }
            )
        }
    }

    private func handleThreadAction(_ action: SidebarItemActionSurface) {
        if action.kind == .rename,
           let item = surface.sidebar.items.first(where: { $0.id == action.threadID }) {
            renameThreadDraft = QuillCodeThreadRenameDraft(threadID: item.id, title: item.title)
            return
        }
        onThreadAction(action)
    }

    private func handleProjectAction(_ action: ProjectItemActionSurface) {
        if action.kind == .rename,
           let item = surface.projects.items.first(where: { $0.id == action.projectID }) {
            renameProjectDraft = QuillCodeProjectRenameDraft(projectID: item.id, name: item.name)
            return
        }
        onProjectAction(action)
    }

    private func handleCommand(_ command: WorkspaceCommandSurface) {
        if command.id == "settings" || command.id == "computer-use-setup" {
            settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
            isSettingsPresented = true
        } else if command.id == "search" {
            searchQuery = ""
            isSearchPresented = true
        } else if command.id == "find-in-chat" {
            isFindPresented = true
        } else if command.id == "add-project" {
            onAddProjectRequested()
        } else if command.id == "command-palette" {
            commandQuery = ""
            isCommandPalettePresented = true
        } else if command.id == "keyboard-shortcuts" {
            isKeyboardShortcutsPresented = true
        } else if command.id == "thread-rename" {
            if let selectedID = surface.sidebar.selectedThreadID,
               let item = surface.sidebar.items.first(where: { $0.id == selectedID }) {
                renameThreadDraft = QuillCodeThreadRenameDraft(threadID: item.id, title: item.title)
            }
        } else if command.id == "project-rename" {
            if let selectedID = surface.projects.selectedProjectID,
               let item = surface.projects.items.first(where: { $0.id == selectedID }) {
                renameProjectDraft = QuillCodeProjectRenameDraft(projectID: item.id, name: item.name)
            }
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

    private func stopActiveRun() {
        if let command = surface.commands.first(where: { $0.id == "stop-all" }) {
            onCommand(command)
        } else {
            onCommand(WorkspaceCommandSurface(
                id: "stop-all",
                title: "Stop all",
                category: WorkspaceCommandPalette.controlCategory,
                keywords: ["cancel", "abort", "halt"]
            ))
        }
    }

    private func useMessageAsDraft(_ text: String) {
        draft = text
        DispatchQueue.main.async {
            isComposerFocused = true
        }
    }

    private func runtimeIssueAction(for issue: RuntimeIssueSurface?) -> (() -> Void)? {
        guard let actionLabel = issue?.actionLabel else { return nil }
        let commandID: String?
        if ["Open Settings", "Add key", "Fix key"].contains(actionLabel) {
            commandID = "settings"
        } else if actionLabel == "Retry" {
            commandID = "retry-last-turn"
        } else if actionLabel == "Switch model" {
            return {
                isModelPickerPresented = true
            }
        } else {
            commandID = nil
        }
        guard let commandID,
              let command = surface.commands.first(where: { $0.id == commandID }),
              command.isEnabled
        else {
            return nil
        }
        return {
            handleCommand(command)
        }
    }
}

private enum QuillCodeWorktreeSheet: String, Identifiable {
    case create
    case remove

    var id: String { rawValue }
}

private struct QuillCodeThreadRenameDraft: Identifiable, Hashable {
    var threadID: UUID
    var title: String

    var id: UUID { threadID }
}

private struct QuillCodeThreadRenameView: View {
    var draft: QuillCodeThreadRenameDraft
    var onCancel: () -> Void
    var onSave: (UUID, String) -> Void

    @State private var title: String

    init(
        draft: QuillCodeThreadRenameDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (UUID, String) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        self._title = State(initialValue: draft.title)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Chat")
                .font(.title2.weight(.semibold))
            TextField("Chat title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canSave {
                        onSave(draft.threadID, title)
                    }
                }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(draft.threadID, title)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}

private struct QuillCodeProjectRenameDraft: Identifiable, Hashable {
    var projectID: UUID
    var name: String

    var id: UUID { projectID }
}

private struct QuillCodeProjectRenameView: View {
    var draft: QuillCodeProjectRenameDraft
    var onCancel: () -> Void
    var onSave: (UUID, String) -> Void

    @State private var name: String

    init(
        draft: QuillCodeProjectRenameDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (UUID, String) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        self._name = State(initialValue: draft.name)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Project")
                .font(.title2.weight(.semibold))
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canSave {
                        onSave(draft.projectID, name)
                    }
                }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(draft.projectID, name)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
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
        case "find-in-chat":
            return "text.magnifyingglass"
        case "add-project":
            return "folder.badge.plus"
        case "project-new-chat":
            return "plus.message"
        case "project-refresh-context":
            return "arrow.clockwise"
        case "project-rename":
            return "text.cursor"
        case "project-remove":
            return "minus.circle"
        case "toggle-terminal":
            return "terminal"
        case "toggle-browser":
            return "globe"
        case "toggle-activity":
            return "list.bullet.rectangle"
        case "toggle-memories", "memory-add":
            return "brain.head.profile"
        case "toggle-extensions":
            return "puzzlepiece.extension"
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
        case "keyboard-shortcuts":
            return "keyboard"
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

private struct QuillCodeKeyboardShortcutsView: View {
    var commands: [WorkspaceCommandSurface]
    var onClose: () -> Void

    private var shortcutCommands: [WorkspaceCommandSurface] {
        commands.filter { $0.shortcut?.isEmpty == false }
    }

    private var groups: [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPalette.groupedCommands(shortcutCommands, matching: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard shortcuts")
                        .font(.title2.weight(.semibold))
                    Text("Fast paths for the workspace actions available right now.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(QuillCodePalette.muted)
                                .textCase(.uppercase)
                            ForEach(group.commands) { command in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(command.title)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(command.isEnabled ? QuillCodePalette.text : QuillCodePalette.muted)
                                        if !command.keywords.isEmpty {
                                            Text(command.keywords.prefix(3).joined(separator: " - "))
                                                .font(.caption)
                                                .foregroundStyle(QuillCodePalette.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text(command.shortcut ?? "")
                                        .font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(QuillCodePalette.text)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(QuillCodePalette.selection)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .padding(12)
                                .background(QuillCodePalette.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.08))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
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
                    Text("Find a thread by title, model, pinned state, archived state, or transcript text.")
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
                                        Text(item.subtitle + (item.isPinned ? " - pinned" : "") + (item.isArchived ? " - archived" : ""))
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
    @Binding var isModelPickerPresented: Bool
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void
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
            QuillCodeModelPickerView(
                topBar: topBar,
                isPresented: $isModelPickerPresented,
                onSetModel: onSetModel,
                onToggleModelFavorite: onToggleModelFavorite
            )
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
            if let runtimeIssueLabel = topBar.runtimeIssueLabel {
                QuillCodePill(
                    text: runtimeIssueLabel,
                    systemImage: "exclamationmark.triangle",
                    tint: topBar.runtimeIssueSeverity == .error ? QuillCodePalette.red : QuillCodePalette.yellow
                )
                .help(runtimeIssueLabel)
            }
            QuillCodePill(text: topBar.instructionLabel, systemImage: topBar.instructionSources.isEmpty ? "doc" : "doc.text.magnifyingglass")
                .help(topBar.instructionSources.isEmpty ? topBar.instructionLabel : topBar.instructionSources.joined(separator: "\n"))
            QuillCodePill(text: topBar.memoryLabel, systemImage: topBar.memorySources.isEmpty ? "brain" : "brain.head.profile")
                .help(topBar.memorySources.isEmpty ? topBar.memoryLabel : topBar.memorySources.joined(separator: "\n"))
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

private struct QuillCodeModelPickerView: View {
    var topBar: TopBarSurface
    @Binding var isPresented: Bool
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredCategories: [ModelCategorySurface] {
        topBar.filteredModelCategories(matching: searchText)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            QuillCodePill(text: topBar.modelLabel, systemImage: "cpu")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose Model")
                            .font(.headline)
                        Text("Search provider, category, or model")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                    Spacer()
                }
                TextField("Search models", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                if filteredCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No models match")
                            .font(.headline)
                        Text("Try a provider, model name, or category.")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(QuillCodePalette.background.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredCategories) { category in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(category.category.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(QuillCodePalette.muted)
                                    ForEach(category.models) { option in
                                        modelRow(option)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 380, height: 440)
            .background(QuillCodePalette.panel)
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } else {
                searchText = ""
                isSearchFocused = false
            }
        }
    }

    private func modelRow(_ option: ModelOptionSurface) -> some View {
        HStack(spacing: 8) {
            Button {
                onSetModel(option.id)
                isPresented = false
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(option.provider)/\(option.displayName)")
                            .font(.callout.weight(.medium))
                        Text(option.id)
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                        if !option.badges.isEmpty {
                            HStack(spacing: 5) {
                                ForEach(option.badges, id: \.self) { badge in
                                    let tint = badgeTint(badge)
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(tint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(tint.opacity(0.14))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Spacer()
                    if option.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(QuillCodePalette.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onToggleModelFavorite(option.id)
            } label: {
                Image(systemName: option.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(option.isFavorite ? QuillCodePalette.yellow : QuillCodePalette.muted)
                    .frame(width: 30, height: 30)
                    .background((option.isFavorite ? QuillCodePalette.yellow : QuillCodePalette.muted).opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
            .help(option.isFavorite ? "Remove favorite" : "Favorite model")
            .accessibilityLabel(option.isFavorite ? "Remove favorite model" : "Favorite model")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(option.isSelected ? QuillCodePalette.selection : QuillCodePalette.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func badgeTint(_ badge: String) -> Color {
        switch badge {
        case "Current":
            QuillCodePalette.green
        case "Favorite":
            QuillCodePalette.yellow
        default:
            QuillCodePalette.blue
        }
    }
}

private struct QuillCodeSidebarView: View {
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
            Divider()
            QuillCodeProjectListView(
                projects: projects,
                onSelectProject: onSelectProject,
                onAddProjectRequested: onAddProjectRequested,
                onProjectAction: onProjectAction
            )
            Divider()
            HStack {
                Text(sidebar.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
                if let action = sidebar.bulkActions.first(where: {
                    sidebar.isSelectionMode ? $0.kind == .clearSelection : $0.kind == .select
                }) {
                    Button(action.title) {
                        onCommand(command(for: action))
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(action.isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .disabled(!action.isEnabled)
                }
            }
            if sidebar.isSelectionMode {
                QuillCodeSidebarBulkActionsView(
                    selectionLabel: sidebar.selectionLabel,
                    actions: sidebar.bulkActions.filter { $0.kind != .clearSelection },
                    onCommand: onCommand
                )
            }
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
                        if !sidebar.recentItems.isEmpty {
                            QuillCodeSidebarThreadSectionView(
                                title: "Recent",
                                items: sidebar.recentItems,
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
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(QuillCodePalette.sidebar)
    }

    private func command(for action: SidebarBulkActionSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: action.commandID,
            title: action.title,
            category: WorkspaceCommandPalette.threadCategory,
            isEnabled: action.isEnabled
        )
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(actions) { action in
                    Button(action.title) {
                        onCommand(command(for: action))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .background((action.isDestructive ? QuillCodePalette.red : QuillCodePalette.panel).opacity(action.isEnabled ? 1 : 0.45))
                    .foregroundStyle(action.isDestructive ? Color.white : QuillCodePalette.text)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(!action.isEnabled)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(QuillCodePalette.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func command(for action: SidebarBulkActionSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: action.commandID,
            title: action.title,
            category: WorkspaceCommandPalette.threadCategory,
            isEnabled: action.isEnabled
        )
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
                    onCommand(WorkspaceCommandSurface(
                        id: "thread-selection-toggle:\(item.id.uuidString)",
                        title: item.isBulkSelected ? "Deselect chat" : "Select chat",
                        category: WorkspaceCommandPalette.threadCategory
                    ))
                } label: {
                    Image(systemName: item.isBulkSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.isBulkSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isBulkSelected ? "Deselect \(item.title)" : "Select \(item.title)")
            }
            Button {
                if isSelectionMode {
                    onCommand(WorkspaceCommandSurface(
                        id: "thread-selection-toggle:\(item.id.uuidString)",
                        title: item.isBulkSelected ? "Deselect chat" : "Select chat",
                        category: WorkspaceCommandPalette.threadCategory
                    ))
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
        commands.filter {
            [
                "new-chat",
                "search",
                "toggle-activity",
                "toggle-browser",
                "toggle-terminal",
                "toggle-memories",
                "toggle-extensions"
            ].contains($0.id)
        }
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
        case "toggle-activity":
            return "list.bullet.rectangle"
        case "toggle-terminal":
            return "terminal"
        case "toggle-browser":
            return "globe"
        case "toggle-memories":
            return "brain.head.profile"
        case "toggle-extensions":
            return "puzzlepiece.extension"
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
    var onProjectAction: (ProjectItemActionSurface) -> Void

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
                    HStack(spacing: 6) {
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
                        }
                        .buttonStyle(.plain)

                        Menu {
                            ForEach(project.actions) { action in
                                Button(role: action.kind == .remove ? .destructive : nil) {
                                    onProjectAction(action)
                                } label: {
                                    Text(action.kind.title)
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
                    .background(project.isSelected ? QuillCodePalette.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct QuillCodeTranscriptView: View {
    var transcript: TranscriptSurface
    var contextBanner: ContextBannerSurface?
    var runtimeIssue: RuntimeIssueSurface?
    var review: WorkspaceReviewSurface
    var retryLastTurnCommand: WorkspaceCommandSurface?
    @Binding var isFindPresented: Bool
    @Binding var findQuery: String
    @Binding var activeFindIndex: Int
    var copiedTranscriptItemID: String?
    var onContextCommand: (WorkspaceCommandSurface) -> Void
    var onRuntimeIssueAction: (() -> Void)?
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onUseMessageAsDraft: (String) -> Void
    var onMessageFeedback: (UUID, MessageFeedbackValue) -> Void

    private var findMatches: [QuillCodeTranscriptFindMatch] {
        QuillCodeTranscriptFindMatch.matches(in: transcript, query: findQuery)
    }

    private var activeFindMatch: QuillCodeTranscriptFindMatch? {
        guard !findMatches.isEmpty else { return nil }
        let boundedIndex = min(max(activeFindIndex, 0), findMatches.count - 1)
        return findMatches[boundedIndex]
    }

    private var latestAssistantMessageID: UUID? {
        transcript.timelineItems
            .compactMap(\.message)
            .last(where: { $0.role == .assistant })?
            .id
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFindPresented {
                QuillCodeTranscriptFindBar(
                    query: $findQuery,
                    activeIndex: activeFindIndex,
                    matchCount: findMatches.count,
                    onPrevious: selectPreviousFindMatch,
                    onNext: selectNextFindMatch,
                    onClose: closeFind
                )
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if transcript.timelineItems.isEmpty && !review.isVisible && contextBanner == nil && runtimeIssue == nil {
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
                            if let runtimeIssue {
                                QuillCodeRuntimeIssueView(
                                    issue: runtimeIssue,
                                    onAction: onRuntimeIssueAction
                                )
                                .frame(maxWidth: 760, alignment: .leading)
                            }
                            if review.isVisible {
                                QuillCodeReviewPaneView(
                                    review: review,
                                    onReviewAction: onReviewAction,
                                    onAddReviewComment: onAddReviewComment
                                )
                            }
                            ForEach(transcript.timelineItems) { item in
                                let isActiveFindItem = activeFindMatch?.timelineItemID == item.id
                                    && !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                Group {
                                    switch item.kind {
                                    case .message:
                                        if let message = item.message {
                                            QuillCodeMessageBubble(
                                                message: message,
                                                timelineItemID: item.id,
                                                isCopied: copiedTranscriptItemID == item.id,
                                                onCopy: {
                                                    onCopyTranscriptItem(item.id, message.text)
                                                },
                                                onUseAsDraft: {
                                                    onUseMessageAsDraft(message.text)
                                                },
                                                canRetry: message.id == latestAssistantMessageID && retryLastTurnCommand != nil,
                                                onRetry: {
                                                    if let retryLastTurnCommand {
                                                        onContextCommand(retryLastTurnCommand)
                                                    }
                                                },
                                                onFeedback: { value in
                                                    onMessageFeedback(message.id, value)
                                                }
                                            )
                                        }
                                    case .toolCard:
                                        if let card = item.toolCard {
                                            QuillCodeToolCardView(
                                                card: card,
                                                isCopied: copiedTranscriptItemID == item.id,
                                                onCopy: {
                                                    onCopyTranscriptItem(item.id, copyText(for: card))
                                                }
                                            )
                                        }
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isActiveFindItem ? QuillCodePalette.blue.opacity(0.75) : Color.clear, lineWidth: 2)
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                }
                .onChange(of: activeFindIndex) { _, _ in
                    scrollToActiveFindMatch(proxy)
                }
                .onChange(of: findQuery) { _, _ in
                    activeFindIndex = 0
                    scrollToActiveFindMatch(proxy)
                }
                .onChange(of: isFindPresented) { _, isPresented in
                    if isPresented {
                        scrollToActiveFindMatch(proxy)
                    }
                }
            }
        }
        .background(QuillCodePalette.background)
    }

    private func copyText(for card: ToolCardState) -> String {
        if let outputJSON = card.outputJSON, !outputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputJSON
        }
        if let inputJSON = card.inputJSON, !inputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inputJSON
        }
        return [card.title, card.subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func selectPreviousFindMatch() {
        guard !findMatches.isEmpty else { return }
        activeFindIndex = (activeFindIndex - 1 + findMatches.count) % findMatches.count
    }

    private func selectNextFindMatch() {
        guard !findMatches.isEmpty else { return }
        activeFindIndex = (activeFindIndex + 1) % findMatches.count
    }

    private func closeFind() {
        isFindPresented = false
        findQuery = ""
        activeFindIndex = 0
    }

    private func scrollToActiveFindMatch(_ proxy: ScrollViewProxy) {
        guard isFindPresented, let activeFindMatch else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(activeFindMatch.timelineItemID, anchor: .center)
            }
        }
    }
}

private struct QuillCodeTranscriptFindMatch: Identifiable, Hashable {
    var id: String { timelineItemID }
    var timelineItemID: String
    var label: String

    static func matches(in transcript: TranscriptSurface, query: String) -> [QuillCodeTranscriptFindMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        return transcript.timelineItems.compactMap { item in
            let haystack = searchableText(for: item)
            guard haystack.localizedCaseInsensitiveContains(normalizedQuery) else { return nil }
            return QuillCodeTranscriptFindMatch(
                timelineItemID: item.id,
                label: label(for: item)
            )
        }
    }

    private static func searchableText(for item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            return [
                item.message?.role.rawValue,
                item.message?.text
            ].compactMap { $0 }.joined(separator: "\n")
        case .toolCard:
            guard let card = item.toolCard else { return "" }
            return [
                card.title,
                card.subtitle,
                card.inputJSON,
                card.outputJSON,
                card.artifacts.map(\.label).joined(separator: "\n")
            ].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private static func label(for item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            return item.message?.role.rawValue.capitalized ?? "Message"
        case .toolCard:
            return item.toolCard?.title ?? "Tool"
        }
    }
}

private struct QuillCodeTranscriptFindBar: View {
    @Binding var query: String
    var activeIndex: Int
    var matchCount: Int
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var statusText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Type to find" }
        guard matchCount > 0 else { return "No results" }
        return "\(min(activeIndex + 1, matchCount)) of \(matchCount)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(QuillCodePalette.blue)
            TextField("Find in chat", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(onNext)
            Text(statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(matchCount > 0 || query.isEmpty ? QuillCodePalette.muted : QuillCodePalette.yellow)
                .frame(minWidth: 86, alignment: .trailing)
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .disabled(matchCount == 0)
            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .disabled(matchCount == 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(QuillCodePalette.panel)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
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
                    Button(banner.compactCommand.title) {
                        onCommand(banner.compactCommand)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!banner.compactCommand.isEnabled)
                    Button(banner.newThreadCommand.title) {
                        onCommand(banner.newThreadCommand)
                    }
                    .buttonStyle(.bordered)
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
    var onStop: () -> Void

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
                    Button("Stop", action: onStop)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(QuillCodePalette.red)
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
                    HStack(spacing: 8) {
                        Text(browser.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if let snapshot = browser.snapshot {
                            Text(snapshot.sourceLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(QuillCodePalette.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(QuillCodePalette.blue.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                    Text(currentURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                    if let snapshot = browser.snapshot {
                        Text(snapshot.summary)
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.text)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(snapshot.details, id: \.self) { detail in
                                Text(detail)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(QuillCodePalette.panel.opacity(0.9))
                                    .clipShape(Capsule())
                            }
                        }
                        if !snapshot.outline.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Page outline")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(QuillCodePalette.muted)
                                ForEach(snapshot.outline.prefix(8), id: \.self) { item in
                                    Text(item)
                                        .font(.caption2)
                                        .foregroundStyle(QuillCodePalette.text)
                                        .lineLimit(1)
                                }
                            }
                        }
                        if let textSnippet = snapshot.textSnippet {
                            Text(textSnippet)
                                .font(.caption2)
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(4)
                        }
                    } else {
                        Text("Ready for page inspection.")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                    }
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
        .frame(height: browser.snapshot == nil ? 260 : 300)
        .background(QuillCodePalette.panel)
    }

    private func addComment() {
        let comment = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return }
        onAddComment(comment)
        commentDraft = ""
    }
}

private struct QuillCodeExtensionsPaneView: View {
    var extensions: WorkspaceExtensionsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(QuillCodePalette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(extensions.title)
                        .font(.headline)
                    Text(extensions.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                HStack(spacing: 6) {
                    countPill(label: "Plugins", count: extensions.pluginCount)
                    countPill(label: "Skills", count: extensions.skillCount)
                    countPill(label: "MCP", count: extensions.mcpServerCount)
                }
            }

            if extensions.items.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(extensions.emptyTitle)
                        .font(.callout.weight(.semibold))
                    Text(extensions.emptySubtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(QuillCodePalette.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(extensions.items) { item in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 6) {
                                    Text(item.kindLabel)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(QuillCodePalette.blue)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(QuillCodePalette.blue.opacity(0.14))
                                        .clipShape(Capsule())
                                    Text(item.statusLabel)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(statusColor(for: item.statusLabel))
                                    Spacer()
                                }
                                Text(item.name)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                if !item.summary.isEmpty {
                                    Text(item.summary)
                                        .font(.caption)
                                        .foregroundStyle(QuillCodePalette.muted)
                                        .lineLimit(2)
                                }
                                Text(item.relativePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(1)
                                if let launchCommand = item.launchCommand {
                                    Text(launchCommand)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(QuillCodePalette.muted)
                                        .lineLimit(1)
                                }
                                if let serverLabel = item.serverLabel {
                                    Text(serverLabel)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(QuillCodePalette.green)
                                        .lineLimit(1)
                                }
                                if let probeError = item.probeError {
                                    Text(probeError)
                                        .font(.caption2)
                                        .foregroundStyle(QuillCodePalette.red)
                                        .lineLimit(2)
                                } else if item.toolCountLabel != nil || item.protocolLabel != nil || !item.toolNames.isEmpty {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 6) {
                                            if let toolCountLabel = item.toolCountLabel {
                                                Text(toolCountLabel)
                                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                                    .foregroundStyle(QuillCodePalette.green)
                                            }
                                            if let protocolLabel = item.protocolLabel {
                                                Text(protocolLabel)
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(QuillCodePalette.muted)
                                            }
                                        }
                                        if !item.toolNames.isEmpty {
                                            HStack(spacing: 5) {
                                                ForEach(item.toolNames, id: \.self) { toolName in
                                                    Text(toolName)
                                                        .font(.caption2.monospaced())
                                                        .foregroundStyle(QuillCodePalette.blue)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(QuillCodePalette.blue.opacity(0.12))
                                                        .clipShape(Capsule())
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                    }
                                }
                                HStack(spacing: 8) {
                                    if let transportLabel = item.transportLabel {
                                        Text(transportLabel)
                                            .font(.caption2.monospaced().weight(.semibold))
                                            .foregroundStyle(QuillCodePalette.muted)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(QuillCodePalette.panel.opacity(0.9))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    if let stopCommandID = item.stopCommandID {
                                        Button("Stop") {
                                            onCommand(extensionCommand(id: stopCommandID, title: "Stop \(item.name)"))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    } else if let startCommandID = item.startCommandID {
                                        Button("Start") {
                                            onCommand(extensionCommand(id: startCommandID, title: "Start \(item.name)"))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(width: 260, alignment: .topLeading)
                            .background(QuillCodePalette.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(height: extensions.items.isEmpty ? 170 : 250)
        .background(QuillCodePalette.panel)
    }

    private func countPill(label: String, count: Int) -> some View {
        Text("\(count) \(label)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(QuillCodePalette.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(QuillCodePalette.blue.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Discovered", "Running", "Ready":
            return QuillCodePalette.green
        case "Probing":
            return QuillCodePalette.blue
        case "Failed", "Missing command":
            return QuillCodePalette.red
        default:
            return QuillCodePalette.muted
        }
    }

    private func extensionCommand(id: String, title: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.extensionsCategory,
            keywords: ["mcp", "server", title]
        )
    }
}

private struct QuillCodeMemoriesPaneView: View {
    var memories: WorkspaceMemoriesSurface
    var onCommand: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(QuillCodePalette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(memories.title)
                        .font(.headline)
                    Text(memories.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                HStack(spacing: 6) {
                    countPill(label: "Global", count: memories.globalCount)
                    countPill(label: "Project", count: memories.projectCount)
                }
                Button {
                    onCommand("memory-add")
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if memories.items.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(memories.emptyTitle)
                        .font(.callout.weight(.semibold))
                    Text(memories.emptySubtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(QuillCodePalette.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(memories.items) { item in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 6) {
                                    Text(item.scopeLabel)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(QuillCodePalette.blue)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(QuillCodePalette.blue.opacity(0.14))
                                        .clipShape(Capsule())
                                    Text(item.byteCountLabel)
                                        .font(.caption2)
                                        .foregroundStyle(QuillCodePalette.muted)
                                    Spacer()
                                    if item.canDelete, let deleteCommandID = item.deleteCommandID {
                                        Button {
                                            onCommand(deleteCommandID)
                                        } label: {
                                            Label("Forget", systemImage: "trash")
                                                .labelStyle(.iconOnly)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(QuillCodePalette.muted)
                                        .help("Forget this global memory")
                                    }
                                }
                                Text(item.title)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Text(item.preview)
                                    .font(.caption)
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(3)
                                Text(item.relativePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(width: 300, alignment: .topLeading)
                            .background(QuillCodePalette.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(height: memories.items.isEmpty ? 170 : 220)
        .background(QuillCodePalette.panel)
    }

    private func countPill(label: String, count: Int) -> some View {
        Text("\(count) \(label)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(QuillCodePalette.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(QuillCodePalette.blue.opacity(0.12))
            .clipShape(Capsule())
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
                    .foregroundStyle(statusColor)
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

    private var statusColor: Color {
        if entry.isSuccess {
            return QuillCodePalette.green
        }
        if entry.isRunning {
            return QuillCodePalette.blue
        }
        if entry.isStopped {
            return QuillCodePalette.muted
        }
        return QuillCodePalette.red
    }
}

private struct QuillCodeReviewPaneView: View {
    var review: WorkspaceReviewSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

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
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

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
                QuillCodeReviewHunkView(
                    hunk: hunk,
                    onReviewAction: onReviewAction,
                    onAddReviewComment: onAddReviewComment
                )
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
                    onAddReviewComment(file.path, nil, nil, nil, text)
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

private struct QuillCodeReviewHunkView: View {
    var hunk: WorkspaceReviewHunkSurface
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    @State private var isAddingRangeComment = false
    @State private var rangeStartDraft = ""
    @State private var rangeEndDraft = ""
    @State private var rangeCommentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(hunk.header)
                    .font(.caption.monospaced())
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                Text(hunk.changeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
                Spacer()
                Button {
                    prepareRangeDraftIfNeeded()
                    isAddingRangeComment.toggle()
                } label: {
                    Label("Add range note", systemImage: "text.bubble.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Add range note")
                .foregroundStyle(QuillCodePalette.blue)
                .disabled(hunk.lines.isEmpty)
                ForEach(hunk.actions) { action in
                    QuillCodeReviewActionButton(action: action, path: hunk.path, onReviewAction: onReviewAction)
                }
            }

            if isAddingRangeComment {
                HStack(spacing: 8) {
                    TextField("From", text: $rangeStartDraft)
                        .textFieldStyle(.plain)
                        .font(.caption.monospacedDigit())
                        .frame(width: 52)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(QuillCodePalette.background.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    TextField("To", text: $rangeEndDraft)
                        .textFieldStyle(.plain)
                        .font(.caption.monospacedDigit())
                        .frame(width: 52)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(QuillCodePalette.background.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    TextField("Range note", text: $rangeCommentDraft)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(QuillCodePalette.background.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Add") {
                        guard let start = Int(rangeStartDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
                              let end = Int(rangeEndDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        else { return }
                        let text = rangeCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAddReviewComment(hunk.path, start, end, nil, text)
                        rangeCommentDraft = ""
                        isAddingRangeComment = false
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canAddRangeComment)
                }
            }

            if !hunk.lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(hunk.lines) { line in
                        QuillCodeReviewLineRowView(
                            line: line,
                            onAddReviewComment: onAddReviewComment
                        )
                    }
                }
                .background(QuillCodePalette.background.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var canAddRangeComment: Bool {
        Int(rangeStartDraft.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && Int(rangeEndDraft.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && !rangeCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prepareRangeDraftIfNeeded() {
        guard rangeStartDraft.isEmpty || rangeEndDraft.isEmpty else { return }
        let lineNumbers = hunk.lines.compactMap(\.displayLineNumber)
        guard let first = lineNumbers.first else { return }
        rangeStartDraft = String(first)
        rangeEndDraft = String(lineNumbers.dropFirst().first ?? first)
    }
}

private struct QuillCodeReviewLineRowView: View {
    var line: WorkspaceReviewLineSurface
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void

    @State private var isAddingComment = false
    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.lineLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
                    .frame(width: 34, alignment: .trailing)
                Text(line.kind.marker)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(markerColor)
                    .frame(width: 10, alignment: .center)
                Text(line.content.isEmpty ? " " : line.content)
                    .font(.caption.monospaced())
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if line.displayLineNumber != nil {
                    Button {
                        isAddingComment.toggle()
                    } label: {
                        Label("Comment on line \(line.lineLabel)", systemImage: "plus.bubble")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Comment on line \(line.lineLabel)")
                    .foregroundStyle(QuillCodePalette.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(lineBackground)

            if !line.comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(line.comments) { comment in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(QuillCodePalette.blue)
                            if let label = comment.lineRangeLabel {
                                Text(label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(QuillCodePalette.muted)
                            }
                            Text(comment.text)
                                .font(.caption)
                                .foregroundStyle(QuillCodePalette.text)
                        }
                    }
                }
                .padding(.leading, 58)
                .padding(.trailing, 8)
            }

            if isAddingComment {
                HStack(spacing: 8) {
                    TextField("Line note", text: $commentDraft)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(QuillCodePalette.panel.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Add") {
                        guard let lineNumber = line.displayLineNumber else { return }
                        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAddReviewComment(line.path, lineNumber, nil, line.kind, text)
                        commentDraft = ""
                        isAddingComment = false
                    }
                    .buttonStyle(.borderless)
                    .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.leading, 58)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .context:
            return QuillCodePalette.muted
        case .insertion:
            return .green
        case .deletion:
            return .red
        }
    }

    private var lineBackground: Color {
        switch line.kind {
        case .context:
            return .clear
        case .insertion:
            return Color.green.opacity(0.08)
        case .deletion:
            return Color.red.opacity(0.08)
        }
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
    var timelineItemID: String
    var isCopied: Bool
    var onCopy: () -> Void
    var onUseAsDraft: () -> Void
    var canRetry: Bool
    var onRetry: () -> Void
    var onFeedback: (MessageFeedbackValue) -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }
            VStack(alignment: actionAlignment, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(message.accessibilityLabel)
                HStack(spacing: 6) {
                    QuillCodeTranscriptCopyButton(
                        label: "Copy",
                        copiedLabel: "Copied",
                        isCopied: isCopied,
                        action: onCopy
                    )
                    .accessibilityIdentifier("transcript-copy-\(timelineItemID)")
                    if message.role == .user {
                        QuillCodeMessageDraftButton(action: onUseAsDraft)
                            .accessibilityIdentifier("message-use-as-draft")
                    }
                    if message.role == .assistant {
                        if canRetry {
                            QuillCodeMessageRetryButton(action: onRetry)
                                .accessibilityIdentifier("message-retry")
                        }
                        QuillCodeMessageFeedbackButton(
                            label: "Helpful",
                            systemImage: "hand.thumbsup",
                            isSelected: message.feedback == .helpful,
                            action: { onFeedback(.helpful) }
                        )
                        QuillCodeMessageFeedbackButton(
                            label: "Not helpful",
                            systemImage: "hand.thumbsdown",
                            isSelected: message.feedback == .notHelpful,
                            action: { onFeedback(.notHelpful) }
                        )
                    }
                }
                .accessibilityIdentifier("message-actions-\(timelineItemID)")
            }
            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var actionAlignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var background: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(LinearGradient(colors: [QuillCodePalette.blue, QuillCodePalette.coral], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(QuillCodePalette.panel)
    }
}

private struct QuillCodeMessageDraftButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Use as draft", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .frame(width: 24, height: 22)
                .foregroundStyle(QuillCodePalette.text)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Use as draft")
    }
}

private struct QuillCodeMessageRetryButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Retry", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .frame(width: 24, height: 22)
                .foregroundStyle(QuillCodePalette.blue)
                .background(QuillCodePalette.blue.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Retry last turn")
    }
}

private struct QuillCodeMessageFeedbackButton: View {
    var label: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .frame(width: 24, height: 22)
                .foregroundStyle(isSelected ? QuillCodePalette.green : QuillCodePalette.muted)
                .background((isSelected ? QuillCodePalette.green : Color.white).opacity(isSelected ? 0.16 : 0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

private struct QuillCodeToolCardView: View {
    var card: ToolCardState
    var isCopied: Bool
    var onCopy: () -> Void
    @State private var isDetailsOpen: Bool

    init(card: ToolCardState, isCopied: Bool = false, onCopy: @escaping () -> Void = {}) {
        self.card = card
        self.isCopied = isCopied
        self.onCopy = onCopy
        self._isDetailsOpen = State(initialValue: card.isExpanded || card.status == .failed || card.status == .review)
    }

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
            HStack {
                QuillCodeTranscriptCopyButton(
                    label: copyActionLabel,
                    copiedLabel: "Copied",
                    isCopied: isCopied,
                    action: onCopy
                )
                Spacer()
            }
            if !card.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Artifacts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(card.artifacts.enumerated()), id: \.offset) { _, artifact in
                                QuillCodeArtifactChip(artifact: artifact)
                            }
                        }
                    }
                }
            }
            if !card.imagePreviewArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Previews")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(card.imagePreviewArtifacts) { artifact in
                            QuillCodeArtifactImagePreview(artifact: artifact)
                        }
                    }
                }
            }

            if card.inputJSON != nil || card.outputJSON != nil {
                DisclosureGroup(isExpanded: $isDetailsOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let inputJSON = card.inputJSON {
                            QuillCodeCodeBlock(title: "Input", text: inputJSON)
                        }
                        if let outputJSON = card.outputJSON {
                            QuillCodeCodeBlock(title: "Output", text: outputJSON)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Text(isDetailsOpen ? "Hide details" : "Show details")
                        if !isDetailsOpen, card.status == .done {
                            Text("Raw tool data")
                                .foregroundStyle(QuillCodePalette.muted)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                }
                .tint(QuillCodePalette.blue)
                .onChange(of: card.status) { _, status in
                    if status == .failed || status == .review || card.isExpanded {
                        isDetailsOpen = true
                    }
                }
                .onChange(of: card.isExpanded) { _, expanded in
                    if expanded {
                        isDetailsOpen = true
                    }
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

    private var copyActionLabel: String {
        if card.outputJSON != nil {
            return "Copy output"
        }
        if card.inputJSON != nil {
            return "Copy input"
        }
        return "Copy"
    }
}

private struct QuillCodeTranscriptCopyButton: View {
    var label: String
    var copiedLabel: String
    var isCopied: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isCopied ? copiedLabel : label, systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isCopied ? QuillCodePalette.green : QuillCodePalette.muted)
                .background((isCopied ? QuillCodePalette.green : Color.white).opacity(isCopied ? 0.16 : 0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isCopied ? copiedLabel : label)
    }
}

private struct QuillCodeArtifactChip: View {
    var artifact: ToolArtifactState

    var body: some View {
        Group {
            if let url = artifactURL {
                Link(destination: url) {
                    label
                }
            } else {
                label
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Artifact \(artifact.label)")
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.label)
                    .lineLimit(1)
                Text(artifact.detail)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(QuillCodePalette.blue)
        .frame(maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(QuillCodePalette.blue.opacity(0.12))
        .overlay(
            Capsule()
                .stroke(QuillCodePalette.blue.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var artifactURL: URL? {
        artifact.href.flatMap(URL.init(string:))
    }

    private var iconName: String {
        switch artifact.kind {
        case .url:
            return "link"
        case .file:
            return "doc.text"
        case .path:
            return "folder"
        }
    }
}

private struct QuillCodeArtifactImagePreview: View {
    var artifact: ToolArtifactState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = previewURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    @unknown default:
                        fallback
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                fallback
            }
            Text(artifact.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(1)
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image preview \(artifact.label)")
    }

    private var previewURL: URL? {
        artifact.previewURL.flatMap(URL.init(string:))
    }

    private var fallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title3)
            Text("Preview unavailable")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(QuillCodePalette.muted)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    var isFocused: FocusState<Bool>.Binding
    var onSend: () -> Void
    var onStop: () -> Void

    @State private var activeSlashSuggestionIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !composer.slashSuggestions.isEmpty {
                QuillCodeSlashSuggestionPanel(
                    suggestions: composer.slashSuggestions,
                    selectedIndex: activeSlashSuggestionIndex
                ) { suggestion in
                    draft = suggestion.insertText
                }
            }
            HStack(spacing: 10) {
                TextField(composer.placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(12)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(composer.isSending)
                    .focused(isFocused)
                    .onKeyPress(.downArrow) {
                        guard !composer.slashSuggestions.isEmpty else { return .ignored }
                        activeSlashSuggestionIndex = min(activeSlashSuggestionIndex + 1, composer.slashSuggestions.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard !composer.slashSuggestions.isEmpty else { return .ignored }
                        activeSlashSuggestionIndex = max(activeSlashSuggestionIndex - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        guard acceptActiveSlashSuggestion(force: true) else { return .ignored }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard acceptActiveSlashSuggestion(force: false) else { return .ignored }
                        return .handled
                    }
                    .onSubmit(onSend)
                if composer.isSending {
                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(minWidth: 78, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(QuillCodePalette.red)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(14)
        .background(QuillCodePalette.panel)
        .onChange(of: draft) { _, _ in
            activeSlashSuggestionIndex = 0
        }
        .onChange(of: composer.slashSuggestions) { _, suggestions in
            if suggestions.isEmpty {
                activeSlashSuggestionIndex = 0
            } else {
                activeSlashSuggestionIndex = min(activeSlashSuggestionIndex, suggestions.count - 1)
            }
        }
    }

    private func acceptActiveSlashSuggestion(force: Bool) -> Bool {
        guard !composer.slashSuggestions.isEmpty else { return false }
        let index = min(max(activeSlashSuggestionIndex, 0), composer.slashSuggestions.count - 1)
        let suggestion = composer.slashSuggestions[index]
        guard force || draft != suggestion.insertText || suggestion.insertText.hasSuffix(" ") else {
            return false
        }
        draft = suggestion.insertText
        return true
    }
}

private struct QuillCodeSlashSuggestionPanel: View {
    var suggestions: [SlashCommandSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (SlashCommandSuggestionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slash commands")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .textCase(.uppercase)
            ForEach(suggestions) { suggestion in
                let isSelected = suggestions.firstIndex(of: suggestion) == selectedIndex
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(suggestion.usage)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(QuillCodePalette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(width: 230, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.callout.weight(.semibold))
                            Text(suggestion.detail)
                                .font(.caption)
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(suggestion.usage), \(suggestion.title)")
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.16))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuillCodeSettingsView: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft
    var onCancel: () -> Void
    var onSave: () -> Void
    var onStartTrustedRouterSignIn: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        ScrollView {
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

                QuillCodeComputerUseSettingsCard(settings: settings, onCommand: onCommand)

                Divider()

                if let issue = settings.runtimeIssue {
                    QuillCodeRuntimeIssueView(issue: issue, showsDiagnostics: true)
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OAuth browser login opens TrustedRouter and returns through QuillCode's local callback. Developer keys stay hidden unless you switch modes.")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                        Button("Sign in with TrustedRouter", action: onStartTrustedRouterSignIn)
                            .buttonStyle(.borderedProminent)
                        Text(settings.signInURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(QuillCodePalette.muted)
                            .textSelection(.enabled)
                    }
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
        }
        .frame(width: 560)
        .frame(maxHeight: 720)
    }
}

private struct QuillCodeComputerUseSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Computer Use")
                        .font(.headline)
                    Text(statusSummary)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.16))
                    .foregroundStyle(statusTint)
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                QuillCodePermissionRow(
                    title: "Screen Recording",
                    detail: "Lets QuillCode inspect the screen for Computer Use.",
                    isGranted: settings.computerUseStatus.screenRecordingGranted,
                    command: settings.computerUseScreenRecordingCommand,
                    onCommand: onCommand
                )
                QuillCodePermissionRow(
                    title: "Accessibility",
                    detail: "Lets QuillCode click, type, scroll, and press keys.",
                    isGranted: settings.computerUseStatus.accessibilityGranted,
                    command: settings.computerUseAccessibilityCommand,
                    onCommand: onCommand
                )
            }

            HStack {
                Button("Refresh status") {
                    onCommand(settings.computerUseRefreshCommand)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .background(QuillCodePalette.panel.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusTint.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusSummary: String {
        if settings.computerUseStatus.available {
            return "Ready for screenshots and desktop input."
        }
        return "Open each required permission below, then return and refresh."
    }

    private var statusLabel: String {
        if settings.computerUseStatus.available {
            return "Ready"
        }
        if !settings.computerUseStatus.screenRecordingGranted && !settings.computerUseStatus.accessibilityGranted {
            return "Setup needed"
        }
        if !settings.computerUseStatus.screenRecordingGranted {
            return "Screen Recording needed"
        }
        return "Accessibility needed"
    }

    private var statusTint: Color {
        settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.yellow
    }
}

private struct QuillCodePermissionRow: View {
    var title: String
    var detail: String
    var isGranted: Bool
    var command: WorkspaceCommandSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? QuillCodePalette.green : QuillCodePalette.yellow)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if isGranted {
                Text("Granted")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(QuillCodePalette.green)
            } else {
                Button("Open") {
                    onCommand(command)
                }
                .buttonStyle(.bordered)
                .disabled(!command.isEnabled)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct QuillCodeRuntimeIssueView: View {
    var issue: RuntimeIssueSurface
    var showsDiagnostics = false
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                if let actionLabel = issue.actionLabel {
                    if let onAction {
                        Button(actionLabel, action: onAction)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    } else {
                        Text(actionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                if showsDiagnostics && !issue.diagnostics.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Diagnostics")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                        ForEach(issue.diagnostics) { diagnostic in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(diagnostic.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .frame(width: 96, alignment: .leading)
                                Text(diagnostic.value)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tint: Color {
        issue.severity == .error ? QuillCodePalette.red : QuillCodePalette.yellow
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
    var tint: Color = QuillCodePalette.blue

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
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

enum QuillCodePalette {
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
