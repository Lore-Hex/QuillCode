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
    public var onTerminalHistoryPrevious: () -> Void
    public var onTerminalHistoryNext: () -> Void
    public var onTerminalResize: (TerminalWindowSize) -> Void
    public var onTerminalSuspend: () -> Void
    public var onTerminalResume: () -> Void
    public var onOpenBrowserPreview: () -> Void
    public var onOpenBrowserSession: (() -> Void)?
    public var onAddBrowserComment: (String) -> Void
    public var onAddProjectRequested: () -> Void
    public var onSelectThread: (UUID) -> Void
    public var onThreadAction: (WorkspaceThreadRowMutation) -> Void
    public var onRenameThread: (UUID, String) -> Void
    public var onSelectProject: (UUID?) -> Void
    public var onProjectAction: (WorkspaceProjectRowMutation) -> Void
    public var onRenameProject: (UUID, String) -> Void
    public var onSetMode: (AgentMode) -> Void
    public var onSetModel: (String) -> Void
    public var onToggleModelFavorite: (String) -> Void
    public var onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    public var onStartTrustedRouterSignIn: () -> Void
    public var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    public var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    public var onPullRequestReviewThreadReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void
    public var onPullRequestReviewDraftChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    public var onCancelPullRequestReviewDraft: () -> Void
    public var onSubmitPullRequestReviewDraft: () -> Void
    public var onToolCardAction: (ToolCardActionSurface) -> Void
    public var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    public var onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    public var onListWorktreeChoices: () async -> WorkspaceWorktreeChoiceLoad
    public var onOpenWorktree: (WorkspaceWorktreeOpenRequest) -> Void
    public var onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    public var onPreviewWorktreePrune: () async -> WorkspaceWorktreePrunePreview
    public var onPruneWorktrees: (WorkspaceWorktreePruneRequest) -> Void
    public var onCopyTranscriptItem: (String, String) -> Void
    public var onExportConversationMarkdown: (String, String) -> Void
    public var onRevertTurn: (UUID) -> Void = { _ in }
    public var onMessageFeedback: (UUID, MessageFeedbackValue) -> Void
    public var onDeleteFollowUp: (UUID) -> Void = { _ in }
    public var onSaveSidebarSavedSearch: (String, String) -> Void
    public var onCommand: (WorkspaceCommandSurface) -> Void

    @State private var isSearchPresented = false
    @State private var isFindPresented = false
    @State private var isModelPickerPresented = false
    @State private var searchQuery = ""
    @State private var findQuery = ""
    @State private var activeFindIndex = 0
    @State private var commandQuery = ""
    @State private var settingsDraft = QuillCodeSettingsDraft()
    @State private var sidebarSavedSearchDraft: QuillCodeSidebarSavedSearchDraft?
    @State private var renameThreadDraft: QuillCodeThreadRenameDraft?
    @State private var renameProjectDraft: QuillCodeProjectRenameDraft?
    @StateObject private var worktreeDialogs = QuillCodeWorktreeDialogCoordinator()
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
        onTerminalHistoryPrevious: @escaping () -> Void = {},
        onTerminalHistoryNext: @escaping () -> Void = {},
        onTerminalResize: @escaping (TerminalWindowSize) -> Void = { _ in },
        onTerminalSuspend: @escaping () -> Void = {},
        onTerminalResume: @escaping () -> Void = {},
        onOpenBrowserPreview: @escaping () -> Void,
        onOpenBrowserSession: (() -> Void)? = nil,
        onAddBrowserComment: @escaping (String) -> Void,
        onAddProjectRequested: @escaping () -> Void,
        onSelectThread: @escaping (UUID) -> Void,
        onThreadAction: @escaping (WorkspaceThreadRowMutation) -> Void,
        onRenameThread: @escaping (UUID, String) -> Void,
        onSelectProject: @escaping (UUID?) -> Void,
        onProjectAction: @escaping (WorkspaceProjectRowMutation) -> Void,
        onRenameProject: @escaping (UUID, String) -> Void,
        onSetMode: @escaping (AgentMode) -> Void,
        onSetModel: @escaping (String) -> Void,
        onToggleModelFavorite: @escaping (String) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onStartTrustedRouterSignIn: @escaping () -> Void,
        onReviewAction: @escaping (WorkspaceReviewActionSurface) -> Void,
        onPullRequestReviewThreadAction: @escaping (WorkspacePullRequestReviewThreadActionSurface) -> Void = { _ in },
        onPullRequestReviewThreadReply: @escaping (WorkspacePullRequestReviewThreadReplyRequest) -> Void = { _ in },
        onPullRequestReviewDraftChange: @escaping (WorkspacePullRequestReviewDraftSurface) -> Void = { _ in },
        onCancelPullRequestReviewDraft: @escaping () -> Void = {},
        onSubmitPullRequestReviewDraft: @escaping () -> Void = {},
        onToolCardAction: @escaping (ToolCardActionSurface) -> Void = { _ in },
        onAddReviewComment: @escaping (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void,
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onListWorktreeChoices: @escaping () async -> WorkspaceWorktreeChoiceLoad = { WorkspaceWorktreeChoiceLoad() },
        onOpenWorktree: @escaping (WorkspaceWorktreeOpenRequest) -> Void,
        onRemoveWorktree: @escaping (WorkspaceWorktreeRemoveRequest) -> Void,
        onPreviewWorktreePrune: @escaping () async -> WorkspaceWorktreePrunePreview = {
            WorkspaceWorktreePrunePreview()
        },
        onPruneWorktrees: @escaping (WorkspaceWorktreePruneRequest) -> Void = { _ in },
        onCopyTranscriptItem: @escaping (String, String) -> Void = { _, _ in },
        onExportConversationMarkdown: @escaping (String, String) -> Void = { _, _ in },
        onRevertTurn: @escaping (UUID) -> Void = { _ in },
        onMessageFeedback: @escaping (UUID, MessageFeedbackValue) -> Void = { _, _ in },
        onDeleteFollowUp: @escaping (UUID) -> Void = { _ in },
        onSaveSidebarSavedSearch: @escaping (String, String) -> Void = { _, _ in },
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
        self.onTerminalHistoryPrevious = onTerminalHistoryPrevious
        self.onTerminalHistoryNext = onTerminalHistoryNext
        self.onTerminalResize = onTerminalResize
        self.onTerminalSuspend = onTerminalSuspend
        self.onTerminalResume = onTerminalResume
        self.onOpenBrowserPreview = onOpenBrowserPreview
        self.onOpenBrowserSession = onOpenBrowserSession
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
        self.onPullRequestReviewThreadAction = onPullRequestReviewThreadAction
        self.onPullRequestReviewThreadReply = onPullRequestReviewThreadReply
        self.onPullRequestReviewDraftChange = onPullRequestReviewDraftChange
        self.onCancelPullRequestReviewDraft = onCancelPullRequestReviewDraft
        self.onSubmitPullRequestReviewDraft = onSubmitPullRequestReviewDraft
        self.onToolCardAction = onToolCardAction
        self.onAddReviewComment = onAddReviewComment
        self.onCreateWorktree = onCreateWorktree
        self.onListWorktreeChoices = onListWorktreeChoices
        self.onOpenWorktree = onOpenWorktree
        self.onRemoveWorktree = onRemoveWorktree
        self.onPreviewWorktreePrune = onPreviewWorktreePrune
        self.onPruneWorktrees = onPruneWorktrees
        self.onCopyTranscriptItem = onCopyTranscriptItem
        self.onExportConversationMarkdown = onExportConversationMarkdown
        self.onRevertTurn = onRevertTurn
        self.onMessageFeedback = onMessageFeedback
        self.onDeleteFollowUp = onDeleteFollowUp
        self.onSaveSidebarSavedSearch = onSaveSidebarSavedSearch
        self.onCommand = onCommand
    }

    public var body: some View {
        VStack(spacing: 0) {
            QuillCodeTopBarView(
                topBar: surface.topBar,
                commands: surface.commands,
                leadingInset: surface.chrome.isSidebarVisible ? QuillCodeMetrics.sidebarWidth : 0,
                onCommand: handleCommand
            )
            Divider()
            HStack(spacing: 0) {
                if surface.chrome.isSidebarVisible {
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
                        .frame(width: QuillCodeMetrics.sidebarWidth)
                    Divider()
                }
                QuillCodeWorkspaceMainPaneView(
                    surface: surface,
                    draft: $draft,
                    terminalDraft: $terminalDraft,
                    browserAddressDraft: $browserAddressDraft,
                    isModelPickerPresented: $isModelPickerPresented,
                    isFindPresented: $isFindPresented,
                    findQuery: $findQuery,
                    activeFindIndex: $activeFindIndex,
                    isComposerFocused: $isComposerFocused,
                    copiedTranscriptItemID: copiedTranscriptItemID,
                    onSetMode: onSetMode,
                    onSetModel: onSetModel,
                    onToggleModelFavorite: onToggleModelFavorite,
                    onSend: onSend,
                    onRunTerminalCommand: onRunTerminalCommand,
                    onTerminalHistoryPrevious: onTerminalHistoryPrevious,
                    onTerminalHistoryNext: onTerminalHistoryNext,
                    onTerminalResize: onTerminalResize,
                    onTerminalSuspend: onTerminalSuspend,
                    onTerminalResume: onTerminalResume,
                    onOpenBrowserPreview: onOpenBrowserPreview,
                    onOpenBrowserSession: onOpenBrowserSession,
                    onAddBrowserComment: onAddBrowserComment,
                    onReviewAction: onReviewAction,
                    onPullRequestReviewThreadAction: onPullRequestReviewThreadAction,
                    onPullRequestReviewThreadReply: onPullRequestReviewThreadReply,
                    onPullRequestReviewDraftChange: onPullRequestReviewDraftChange,
                    onCancelPullRequestReviewDraft: onCancelPullRequestReviewDraft,
                    onSubmitPullRequestReviewDraft: onSubmitPullRequestReviewDraft,
                    onToolCardAction: onToolCardAction,
                    onAddReviewComment: onAddReviewComment,
                    onCopyTranscriptItem: onCopyTranscriptItem,
                    onRevertTurn: onRevertTurn,
                    onMessageFeedback: onMessageFeedback,
                    onDeleteFollowUp: onDeleteFollowUp,
                    onCommand: handleCommand
                )
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .onChange(of: surface.composer.focusToken) { _, _ in
            // The `focus-composer` (Cmd+L) command bumps this token; grab focus when it changes.
            isComposerFocused = true
        }
        .quillCodeWorkspaceSheets(
            surface: surface,
            isSearchPresented: $isSearchPresented,
            searchQuery: $searchQuery,
            isCommandPalettePresented: $isCommandPalettePresented,
            commandQuery: $commandQuery,
            isSettingsPresented: $isSettingsPresented,
            settingsDraft: $settingsDraft,
            isKeyboardShortcutsPresented: $isKeyboardShortcutsPresented,
            worktreeSheet: $worktreeDialogs.sheet,
            createWorktreeDraft: $worktreeDialogs.createDraft,
            openWorktreeDraft: $worktreeDialogs.openDraft,
            removeWorktreeDraft: $worktreeDialogs.removeDraft,
            pruneWorktreeDraft: $worktreeDialogs.pruneDraft,
            renameThreadDraft: $renameThreadDraft,
            renameProjectDraft: $renameProjectDraft,
            sidebarSavedSearchDraft: $sidebarSavedSearchDraft,
            onSelectThread: onSelectThread,
            onSaveSettings: onSaveSettings,
            onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
            onCommand: handleCommand,
            onCreateWorktree: onCreateWorktree,
            onRetryWorktreeChoices: retryWorktreeChoices,
            onOpenWorktree: onOpenWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRetryWorktreePrunePreview: retryWorktreePrunePreview,
            onPruneWorktrees: onPruneWorktrees,
            onRenameThread: onRenameThread,
            onRenameProject: onRenameProject,
            onSaveSidebarSavedSearch: onSaveSidebarSavedSearch
        )
    }

    private func handleThreadAction(_ action: SidebarItemActionSurface) {
        guard let action = WorkspaceSidebarRowActionPlanner(
            sidebar: surface.sidebar,
            projects: surface.projects
        ).action(for: action) else { return }
        handleSidebarRowAction(action)
    }

    private func handleProjectAction(_ action: ProjectItemActionSurface) {
        guard let action = WorkspaceSidebarRowActionPlanner(
            sidebar: surface.sidebar,
            projects: surface.projects
        ).action(for: action) else { return }
        handleSidebarRowAction(action)
    }

    private func handleSidebarRowAction(_ action: WorkspaceSidebarRowAction) {
        switch action {
        case let .renameThread(threadID, title):
            renameThreadDraft = QuillCodeThreadRenameDraft(threadID: threadID, title: title)
        case let .mutateThread(mutation):
            onThreadAction(mutation)
        case let .renameProject(projectID, name):
            renameProjectDraft = QuillCodeProjectRenameDraft(projectID: projectID, name: name)
        case let .mutateProject(mutation):
            onProjectAction(mutation)
        }
    }

    private func handleCommand(_ command: WorkspaceCommandSurface) {
        guard let action = WorkspaceViewCommandPlanner(
            sidebar: surface.sidebar,
            projects: surface.projects
        ).action(for: command) else {
            return
        }
        handleCommandAction(action)
    }

    private func handleCommandAction(_ action: WorkspaceViewCommandAction) {
        switch action {
        case .presentSettings:
            settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
            isSettingsPresented = true
        case .presentSearch:
            searchQuery = ""
            isSearchPresented = true
        case .presentFind:
            isFindPresented = true
        case .requestAddProject:
            onAddProjectRequested()
        case .presentCommandPalette:
            commandQuery = ""
            isCommandPalettePresented = true
        case .presentKeyboardShortcuts:
            isKeyboardShortcutsPresented = true
        case .presentSidebarSavedSearch:
            sidebarSavedSearchDraft = QuillCodeSidebarSavedSearchDraft()
        case let .renameThread(threadID, title):
            renameThreadDraft = QuillCodeThreadRenameDraft(threadID: threadID, title: title)
        case let .renameProject(projectID, name):
            renameProjectDraft = QuillCodeProjectRenameDraft(projectID: projectID, name: name)
        case .presentCreateWorktree:
            worktreeDialogs.presentCreate()
        case .presentOpenWorktree:
            worktreeDialogs.presentOpen(loadChoices: onListWorktreeChoices)
        case .presentRemoveWorktree:
            worktreeDialogs.presentRemove(loadChoices: onListWorktreeChoices)
        case .presentPruneWorktrees:
            worktreeDialogs.presentPrune(loadPreview: onPreviewWorktreePrune)
        case .openBrowserSession:
            onOpenBrowserSession?()
        case .copyConversation:
            // Reuses the existing per-item copy closure (-> controller -> pasteboard),
            // so the whole-conversation export shares the same copy path and feedback.
            if let markdown = TranscriptMarkdownExporter.clipboardMarkdown(for: surface.transcript) {
                onCopyTranscriptItem("conversation", markdown)
            }
        case .exportConversationMarkdown:
            if let markdown = TranscriptMarkdownExporter.exportableMarkdown(for: surface.transcript) {
                onExportConversationMarkdown(surface.topBar.primaryTitle, markdown)
            }
        case let .dispatch(command, focusesComposer):
            onCommand(command)
            if focusesComposer {
                DispatchQueue.main.async {
                    isComposerFocused = true
                }
            }
        }
    }

    private func retryWorktreeChoices(for sheet: QuillCodeWorktreeSheet) {
        worktreeDialogs.retryChoices(for: sheet, loadChoices: onListWorktreeChoices)
    }

    private func retryWorktreePrunePreview() {
        worktreeDialogs.retryPrunePreview(loadPreview: onPreviewWorktreePrune)
    }
}

extension AgentMode {
    var title: String {
        switch self {
        case .readOnly:
            return "Read-only"
        case .review:
            return "Review"
        case .plan:
            return "Plan"
        case .auto:
            return "Auto"
        }
    }
}
