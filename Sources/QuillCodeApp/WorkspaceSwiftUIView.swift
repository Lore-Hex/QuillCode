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
        guard let action = RuntimeIssueRecoveryPlanner(commands: surface.commands).action(for: issue) else {
            return nil
        }
        switch action {
        case .presentModelPicker:
            return {
                isModelPickerPresented = true
            }
        case let .command(command):
            return {
                handleCommand(command)
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
