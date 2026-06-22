import SwiftUI
import QuillCodeCore
import QuillCodeTools

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
                        if surface.automations.isVisible {
                            QuillCodeAutomationsPaneView(
                                automations: surface.automations,
                                onCommand: handleCommand
                            )
                            Divider()
                        }
                        if !surface.automations.isVisible || !surface.transcript.timelineItems.isEmpty {
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
                        } else {
                            Spacer(minLength: 0)
                        }
                        if surface.browser.isVisible {
                            Divider()
                            QuillCodeBrowserPaneView(
                                browser: surface.browser,
                                addressDraft: $browserAddressDraft,
                                onOpen: onOpenBrowserPreview,
                                onAddComment: onAddBrowserComment,
                                onCommand: runCommand(id:)
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
                                onStop: stopActiveRun,
                                onClear: { runCommand(id: "terminal-clear") }
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
                        QuillCodeActivityPaneView(activity: surface.activity) { commandID in
                            handleCommand(WorkspaceCommandSurface(
                                id: commandID,
                                title: "Toggle activity section",
                                category: WorkspaceCommandPalette.workspaceCategory,
                                keywords: ["activity", "task", "collapse", "expand"]
                            ))
                        }
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
            let shouldFocusComposer = SlashCommandCatalog.insertText(forCommandPaletteID: command.id) != nil
                || command.id == "memory-add"
                || command.id == "add-ssh-project"
                || command.id == "project-rename"
                || command.id == "thread-rename"
            onCommand(command)
            if shouldFocusComposer {
                DispatchQueue.main.async {
                    isComposerFocused = true
                }
            }
        }
    }

    private func runCommand(id: String) {
        guard let command = surface.commands.first(where: { $0.id == id }) else { return }
        handleCommand(command)
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
    @FocusState private var isSearchFocused: Bool

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
                    Text("Run actions, or type / to insert slash commands.")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                TextField("Search commands, > actions, / slash", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onSubmit(selectHighlightedCommand)
                if let label = activeScopeLabel {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(QuillCodePalette.selection)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

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
        .onAppear {
            ensureSelection()
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onDisappear {
            isSearchFocused = false
        }
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
        .help(command.keywords.last ?? command.title)
    }

    private var activeScopeLabel: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return "Slash"
        }
        if trimmed.hasPrefix(">") {
            return "Actions"
        }
        return nil
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
        case _ where commandID.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix):
            return "slash.circle"
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
        case "terminal-clear":
            return "clear"
        case "toggle-browser":
            return "globe"
        case "toggle-activity":
            return "list.bullet.rectangle"
        case "toggle-automations":
            return "clock.arrow.circlepath"
        case "toggle-memories", "memory-add":
            return "brain.head.profile"
        case "toggle-extensions":
            return "puzzlepiece.extension"
        case "git-pr-create":
            return "arrow.up.doc"
        case "git-pr-checkout":
            return "arrow.down.doc"
        case "git-pr-reviewers":
            return "person.2.badge.gearshape"
        case "git-pr-labels":
            return "tag"
        case "git-pr-merge":
            return "arrow.triangle.merge"
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

    @FocusState private var isSearchFocused: Bool

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
                .focused($isSearchFocused)
                .onSubmit {
                    if let firstResult = results.first {
                        onSelectThread(firstResult.id)
                    }
                }

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
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onDisappear {
            isSearchFocused = false
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var isEmptyStateVisible: Bool {
        transcript.timelineItems.isEmpty && !review.isVisible && contextBanner == nil && runtimeIssue == nil
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
            if isEmptyStateVisible {
                Spacer(minLength: 0)
                emptyState
                    .padding(.bottom, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
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
        }
        .background(QuillCodePalette.background)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(transcript.emptyTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
            Text(transcript.emptySubtitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
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
            quillCodeWithAnimation(.easeInOut(duration: 0.18), reduceMotion: reduceMotion) {
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
    var onClear: () -> Void

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
                Button("Clear", action: onClear)
                    .controlSize(.small)
                    .disabled(!terminal.canClear)
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
    var onCommand: (String) -> Void

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
                browserNavigationButton(
                    systemName: "chevron.left",
                    label: "Back",
                    isEnabled: browser.canGoBack
                ) {
                    onCommand("browser-back")
                }
                browserNavigationButton(
                    systemName: "chevron.right",
                    label: "Forward",
                    isEnabled: browser.canGoForward
                ) {
                    onCommand("browser-forward")
                }
                browserNavigationButton(
                    systemName: "arrow.clockwise",
                    label: "Reload",
                    isEnabled: browser.canReload
                ) {
                    onCommand("browser-reload")
                }
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
                            browserBadge(snapshot.sourceLabel, tint: QuillCodePalette.blue)
                            browserBadge(
                                snapshot.inspectionDepthLabel,
                                tint: browserInspectionTint(snapshot.inspectionDepth)
                            )
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
                .quillCodeSurface(
                    fill: QuillCodePalette.background.opacity(0.7),
                    radius: 20,
                    stroke: Color.white.opacity(0.08),
                    shadow: false
                )
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
                            .quillCodeSurface(
                                fill: QuillCodePalette.background.opacity(0.7),
                                radius: 18,
                                stroke: Color.white.opacity(0.08),
                                shadow: false
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(height: browser.snapshot == nil ? 260 : 300)
        .background(QuillCodePalette.panel)
    }

    private func browserNavigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(
                    minWidth: QuillCodeMetrics.minimumHitTarget,
                    minHeight: QuillCodeMetrics.minimumHitTarget
                )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func addComment() {
        let comment = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return }
        onAddComment(comment)
        commentDraft = ""
    }

    private func browserBadge(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func browserInspectionTint(_ depth: BrowserInspectionDepth) -> Color {
        switch depth {
        case .metadataOnly:
            return QuillCodePalette.yellow
        case .fileMetadata:
            return QuillCodePalette.blue
        case .staticHTMLSnapshot:
            return QuillCodePalette.green
        }
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
                                        .foregroundStyle(QuillCodePalette.muted)
                                    Text(item.statusLabel)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(statusColor(for: item.statusLabel))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(statusColor(for: item.statusLabel).opacity(0.14))
                                        .clipShape(Capsule())
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
                                if let versionLabel = item.versionLabel {
                                    Text(versionLabel)
                                        .font(.caption2.monospaced().weight(.semibold))
                                        .foregroundStyle(QuillCodePalette.green)
                                        .lineLimit(1)
                                }
                                if let sourceURL = item.sourceURL {
                                    Text(sourceURL)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(QuillCodePalette.muted)
                                        .lineLimit(1)
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
                                        .foregroundStyle(QuillCodePalette.muted)
                                        .lineLimit(1)
                                }
                                if let probeError = item.probeError {
                                    Text(probeError)
                                        .font(.caption2)
                                        .foregroundStyle(QuillCodePalette.red)
                                        .lineLimit(2)
                                } else if item.hasMCPProbeMetadata {
                                    VStack(alignment: .leading, spacing: 5) {
                                        probeMetadataCounts(for: item)
                                        probeMetadataChips(for: item)
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
                                    if let updateCommandID = item.updateCommandID {
                                        Button("Update") {
                                            onCommand(extensionCommand(id: updateCommandID, title: "Update \(item.name)"))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
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
                            .frame(width: 280, alignment: .topLeading)
                            .background(QuillCodePalette.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(height: extensions.items.isEmpty ? 170 : 280)
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

    @ViewBuilder
    private func probeMetadataCounts(for item: ProjectExtensionManifestSurface) -> some View {
        let labels = [
            item.protocolLabel,
            item.toolCountLabel,
            item.resourceCountLabel,
            item.promptCountLabel
        ].compactMap { $0 }

        if !labels.isEmpty {
            Text(labels.joined(separator: " · "))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func probeMetadataChips(for item: ProjectExtensionManifestSurface) -> some View {
        if !item.toolNames.isEmpty || !item.resourceNames.isEmpty || !item.promptNames.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                probeMetadataToolGroup(tools: item.toolDescriptors)
                probeMetadataGroup(title: "Resources", values: item.resourceNames)
                probeMetadataGroup(title: "Prompts", values: item.promptNames)
            }
        }
    }

    @ViewBuilder
    private func probeMetadataToolGroup(tools: [MCPToolDescriptor]) -> some View {
        if !tools.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tools")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(QuillCodePalette.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !tool.schemaSummary.isEmpty || !tool.description.isEmpty {
                                Text([tool.schemaSummary, tool.description].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(QuillCodePalette.blue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func probeMetadataGroup(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(QuillCodePalette.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(QuillCodePalette.blue.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
            }
        }
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

private extension ProjectExtensionManifestSurface {
    var hasMCPProbeMetadata: Bool {
        toolCountLabel != nil
            || resourceCountLabel != nil
            || promptCountLabel != nil
            || protocolLabel != nil
            || !toolDescriptors.isEmpty
            || !resourceNames.isEmpty
            || !promptNames.isEmpty
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

private struct QuillCodeAutomationsPaneView: View {
    var automations: WorkspaceAutomationsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(QuillCodePalette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(automations.title)
                        .font(.headline)
                    Text(automations.subtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(2)
                }
                Spacer()
                if automations.createThreadFollowUpCommand != nil
                    || automations.createWorkspaceScheduleCommand != nil
                    || !automations.scheduleThreadFollowUpCommands.isEmpty
                    || !automations.scheduleWorkspaceScheduleCommands.isEmpty {
                    Menu {
                        if let createCommand = automations.createThreadFollowUpCommand {
                            Button(createCommand.title) {
                                onCommand(createCommand)
                            }
                            .disabled(!createCommand.isEnabled)
                        }
                        if let createCommand = automations.createWorkspaceScheduleCommand {
                            Button(createCommand.title) {
                                onCommand(createCommand)
                            }
                            .disabled(!createCommand.isEnabled)
                        }
                        if !automations.scheduleThreadFollowUpCommands.isEmpty {
                            Divider()
                            ForEach(automations.scheduleThreadFollowUpCommands, id: \.id) { command in
                                Button(command.title) {
                                    onCommand(command)
                                }
                                .disabled(!command.isEnabled)
                            }
                        }
                        if !automations.scheduleWorkspaceScheduleCommands.isEmpty {
                            Divider()
                            ForEach(automations.scheduleWorkspaceScheduleCommands, id: \.id) { command in
                                Button(command.title) {
                                    onCommand(command)
                                }
                                .disabled(!command.isEnabled)
                            }
                        }
                    } label: {
                        Label("Create", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text(automations.statusLabel)
                    .font(.caption.weight(.semibold))
                    .fontDesign(.rounded)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(QuillCodePalette.blue.opacity(0.14))
                    .foregroundStyle(QuillCodePalette.blue)
                    .clipShape(Capsule())
            }

            if automations.workflows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(automations.emptyTitle)
                        .font(.callout.weight(.semibold))
                    Text(automations.emptySubtitle)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(QuillCodePalette.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(automations.workflows) { workflow in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(workflow.scheduleLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(QuillCodePalette.blue)
                                Spacer()
                                Text(workflow.statusLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(QuillCodePalette.muted)
                            }
                            Text(workflow.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(workflow.detail)
                                .font(.caption)
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(3)
                            if workflow.runCommandID != nil || workflow.primaryCommandID != nil || workflow.deleteCommandID != nil {
                                Divider()
                                HStack(spacing: 8) {
                                    if let commandID = workflow.runCommandID,
                                       let actionTitle = workflow.runActionTitle {
                                        Button(actionTitle) {
                                            onCommand(automationCommand(id: commandID, title: actionTitle))
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    if let commandID = workflow.primaryCommandID,
                                       let actionTitle = workflow.primaryActionTitle {
                                        Button(actionTitle) {
                                            onCommand(automationCommand(id: commandID, title: actionTitle))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if let commandID = workflow.deleteCommandID {
                                        Button("Delete", role: .destructive) {
                                            onCommand(automationCommand(id: commandID, title: "Delete automation"))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .background(QuillCodePalette.background.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .frame(minHeight: 190)
        .background(QuillCodePalette.panel)
    }

    private func automationCommand(id: String, title: String) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "schedule", "follow-up"]
        )
    }
}

private struct QuillCodeTerminalEntryView: View {
    var entry: TerminalCommandSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 8) {
                    Text("$ \(entry.command)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    if let executionContext = entry.executionContext {
                        QuillCodeExecutionContextChip(context: executionContext)
                    }
                }
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
        .overlay(alignment: .leading) {
            if let executionContext = entry.executionContext {
                QuillCodeExecutionRail(context: executionContext)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
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

    private var accessibilityLabel: String {
        let context = entry.executionContext.map {
            ", \($0.label) \($0.detail)"
        } ?? ""
        return "\(entry.command), \(entry.statusLabel), \(entry.exitCodeLabel)\(context)"
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

extension AgentMode {
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
