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
    @Binding public var isSearchPresented: Bool
    @Binding public var isFindPresented: Bool
    @Binding public var isModelPickerPresented: Bool
    public var copiedTranscriptItemID: String?
    public var actions: QuillCodeWorkspaceActions

    @State private var searchQuery = ""
    @State private var findQuery = ""
    @State private var activeFindIndex = 0
    @State private var commandQuery = ""
    @State private var settingsDraft = QuillCodeSettingsDraft()
    @State private var sidebarSavedSearchDraft: QuillCodeSidebarSavedSearchDraft?
    @State private var renameThreadDraft: QuillCodeThreadRenameDraft?
    @State private var renameProjectDraft: QuillCodeProjectRenameDraft?
    @State private var subagentTranscript: WorkspaceSubagentTranscriptSurface?
    @StateObject private var worktreeDialogs = QuillCodeWorktreeDialogCoordinator()
    @StateObject private var agentImportDialog = QuillCodeAgentImportDialogCoordinator()
    @FocusState private var isComposerFocused: Bool

    public init(
        surface: WorkspaceSurface,
        draft: Binding<String>,
        terminalDraft: Binding<String>,
        browserAddressDraft: Binding<String>,
        isCommandPalettePresented: Binding<Bool>,
        isSettingsPresented: Binding<Bool>,
        isKeyboardShortcutsPresented: Binding<Bool>,
        isSearchPresented: Binding<Bool> = .constant(false),
        isFindPresented: Binding<Bool> = .constant(false),
        isModelPickerPresented: Binding<Bool> = .constant(false),
        copiedTranscriptItemID: String? = nil,
        onSend: @escaping () -> Void,
        onAddImagesRequested: @escaping () -> Void = {},
        onRemoveImage: @escaping (UUID) -> Void = { _ in },
        onRunTerminalCommand: @escaping () -> Void,
        onTerminalHistoryPrevious: @escaping () -> Void = {},
        onTerminalHistoryNext: @escaping () -> Void = {},
        onTerminalResize: @escaping (TerminalWindowSize) -> Void = { _ in },
        onTerminalMouseInput: @escaping (TerminalMouseInputRequest) -> Void = { _ in },
        onTerminalKeyboardInput: @escaping (TerminalKeyboardInputRequest) -> Void = { _ in },
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
        onMoveProjectBefore: @escaping (UUID, UUID) -> Bool = { _, _ in false },
        onMoveProjectToBottom: @escaping (UUID) -> Bool = { _ in false },
        onRenameProject: @escaping (UUID, String) -> Void,
        onSetMode: @escaping (AgentMode) -> Void,
        onSetModel: @escaping (String) -> Void,
        onToggleModelFavorite: @escaping (String) -> Void,
        onSaveSettings: @escaping (WorkspaceSettingsUpdate) -> Void,
        onSaveKeyboardShortcuts: @escaping (KeyboardShortcutPreferences) -> Void = { _ in },
        onStartTrustedRouterSignIn: @escaping () -> Void,
        agentImportActions: QuillCodeAgentImportActions? = nil,
        onReviewScopeChange: @escaping (WorkspaceReviewSelection) -> Void = { _ in },
        onReviewAction: @escaping (WorkspaceReviewActionSurface) -> Void,
        onPullRequestReviewThreadAction: @escaping (WorkspacePullRequestReviewThreadActionSurface) -> Void = { _ in },
        onPullRequestReviewThreadReply: @escaping (WorkspacePullRequestReviewThreadReplyRequest) -> Void = { _ in },
        onPullRequestReviewDraftChange: @escaping (WorkspacePullRequestReviewDraftSurface) -> Void = { _ in },
        onCancelPullRequestReviewDraft: @escaping () -> Void = {},
        onSubmitPullRequestReviewDraft: @escaping () -> Void = {},
        onToolCardAction: @escaping (ToolCardActionSurface) -> Void = { _ in },
        onAddReviewComment: @escaping (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void,
        onCreateWorktreeThread: @escaping (WorkspaceNewWorktreeThreadRequest) -> Void = { _ in },
        onCreateWorktree: @escaping (WorkspaceWorktreeCreateRequest) -> Void,
        onCreateWorktreeBranch: @escaping (WorkspaceWorktreeCreateBranchRequest) -> Void = { _ in },
        onFinishWorktree: @escaping () -> Void = {},
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
        onDeleteFollowUp: @escaping (UUID) -> Void = { _ in },
        onSaveSidebarSavedSearch: @escaping (String, String) -> Void = { _, _ in },
        onOpenAttentionDigest: @escaping (UUID) -> Void = { _ in },
        onCloseAttentionDigest: @escaping () -> Void = {},
        onLoadSubagentTranscript: @escaping (UUID, UUID, String) -> WorkspaceSubagentTranscriptSurface? = { _, _, _ in nil },
        onCommand: @escaping (WorkspaceCommandSurface) -> Void
    ) {
        self.surface = surface
        self._draft = draft
        self._terminalDraft = terminalDraft
        self._browserAddressDraft = browserAddressDraft
        self._isCommandPalettePresented = isCommandPalettePresented
        self._isSettingsPresented = isSettingsPresented
        self._isKeyboardShortcutsPresented = isKeyboardShortcutsPresented
        self._isSearchPresented = isSearchPresented
        self._isFindPresented = isFindPresented
        self._isModelPickerPresented = isModelPickerPresented
        self.copiedTranscriptItemID = copiedTranscriptItemID
        self.actions = QuillCodeWorkspaceActions(
            onSend: onSend,
            onAddImagesRequested: onAddImagesRequested,
            onRemoveImage: onRemoveImage,
            onRunTerminalCommand: onRunTerminalCommand,
            onTerminalHistoryPrevious: onTerminalHistoryPrevious,
            onTerminalHistoryNext: onTerminalHistoryNext,
            onTerminalResize: onTerminalResize,
            onTerminalMouseInput: onTerminalMouseInput,
            onTerminalKeyboardInput: onTerminalKeyboardInput,
            onTerminalSuspend: onTerminalSuspend,
            onTerminalResume: onTerminalResume,
            onOpenBrowserPreview: onOpenBrowserPreview,
            onOpenBrowserSession: onOpenBrowserSession,
            onAddBrowserComment: onAddBrowserComment,
            onAddProjectRequested: onAddProjectRequested,
            onSelectThread: onSelectThread,
            onThreadAction: onThreadAction,
            onRenameThread: onRenameThread,
            onSelectProject: onSelectProject,
            onProjectAction: onProjectAction,
            onMoveProjectBefore: onMoveProjectBefore,
            onMoveProjectToBottom: onMoveProjectToBottom,
            onRenameProject: onRenameProject,
            onSetMode: onSetMode,
            onSetModel: onSetModel,
            onToggleModelFavorite: onToggleModelFavorite,
            onSaveSettings: onSaveSettings,
            onSaveKeyboardShortcuts: onSaveKeyboardShortcuts,
            onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
            agentImport: agentImportActions,
            onReviewScopeChange: onReviewScopeChange,
            onReviewAction: onReviewAction,
            onPullRequestReviewThreadAction: onPullRequestReviewThreadAction,
            onPullRequestReviewThreadReply: onPullRequestReviewThreadReply,
            onPullRequestReviewDraftChange: onPullRequestReviewDraftChange,
            onCancelPullRequestReviewDraft: onCancelPullRequestReviewDraft,
            onSubmitPullRequestReviewDraft: onSubmitPullRequestReviewDraft,
            onToolCardAction: onToolCardAction,
            onAddReviewComment: onAddReviewComment,
            onCreateWorktreeThread: onCreateWorktreeThread,
            onCreateWorktree: onCreateWorktree,
            onCreateWorktreeBranch: onCreateWorktreeBranch,
            onFinishWorktree: onFinishWorktree,
            onListWorktreeChoices: onListWorktreeChoices,
            onOpenWorktree: onOpenWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onPreviewWorktreePrune: onPreviewWorktreePrune,
            onPruneWorktrees: onPruneWorktrees,
            onCopyTranscriptItem: onCopyTranscriptItem,
            onExportConversationMarkdown: onExportConversationMarkdown,
            onRevertTurn: onRevertTurn,
            onDeleteFollowUp: onDeleteFollowUp,
            onSaveSidebarSavedSearch: onSaveSidebarSavedSearch,
            onOpenAttentionDigest: onOpenAttentionDigest,
            onCloseAttentionDigest: onCloseAttentionDigest,
            onLoadSubagentTranscript: onLoadSubagentTranscript,
            onCommand: onCommand
        )
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
                        onSelectProject: actions.onSelectProject,
                        onAddProjectRequested: actions.onAddProjectRequested,
                        onProjectAction: handleProjectAction,
                        onMoveProjectBefore: actions.onMoveProjectBefore,
                        onMoveProjectToBottom: actions.onMoveProjectToBottom,
                        onSelectThread: actions.onSelectThread,
                        onThreadAction: handleThreadAction,
                        onCommand: handleCommand,
                        onOpenAttentionDigest: actions.onOpenAttentionDigest
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
                    onSetMode: actions.onSetMode,
                    onSetModel: actions.onSetModel,
                    onToggleModelFavorite: actions.onToggleModelFavorite,
                    onSend: handleComposerSend,
                    onAddImagesRequested: actions.onAddImagesRequested,
                    onRemoveImage: actions.onRemoveImage,
                    onRunTerminalCommand: actions.onRunTerminalCommand,
                    onTerminalHistoryPrevious: actions.onTerminalHistoryPrevious,
                    onTerminalHistoryNext: actions.onTerminalHistoryNext,
                    onTerminalResize: actions.onTerminalResize,
                    onTerminalMouseInput: actions.onTerminalMouseInput,
                    onTerminalKeyboardInput: actions.onTerminalKeyboardInput,
                    onTerminalSuspend: actions.onTerminalSuspend,
                    onTerminalResume: actions.onTerminalResume,
                    onOpenBrowserPreview: actions.onOpenBrowserPreview,
                    onOpenBrowserSession: actions.onOpenBrowserSession,
                    onAddBrowserComment: actions.onAddBrowserComment,
                    onReviewScopeChange: actions.onReviewScopeChange,
                    onReviewAction: actions.onReviewAction,
                    onPullRequestReviewThreadAction: actions.onPullRequestReviewThreadAction,
                    onPullRequestReviewThreadReply: actions.onPullRequestReviewThreadReply,
                    onPullRequestReviewDraftChange: actions.onPullRequestReviewDraftChange,
                    onCancelPullRequestReviewDraft: actions.onCancelPullRequestReviewDraft,
                    onSubmitPullRequestReviewDraft: actions.onSubmitPullRequestReviewDraft,
                    onToolCardAction: actions.onToolCardAction,
                    onAddReviewComment: actions.onAddReviewComment,
                    onCopyTranscriptItem: actions.onCopyTranscriptItem,
                    onRevertTurn: actions.onRevertTurn,
                    onDeleteFollowUp: actions.onDeleteFollowUp,
                    onCommand: handleCommand
                )
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .dynamicTypeSize(surface.chrome.textScale.dynamicTypeSize)
        .overlay {
            if let digest = surface.attentionDigest {
                attentionDigestOverlay(digest)
            }
        }
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
            newWorktreeTaskDraft: $worktreeDialogs.newTaskDraft,
            createWorktreeDraft: $worktreeDialogs.createDraft,
            createWorktreeBranchDraft: $worktreeDialogs.createBranchDraft,
            finishWorktreeDraft: $worktreeDialogs.finishDraft,
            openWorktreeDraft: $worktreeDialogs.openDraft,
            removeWorktreeDraft: $worktreeDialogs.removeDraft,
            pruneWorktreeDraft: $worktreeDialogs.pruneDraft,
            renameThreadDraft: $renameThreadDraft,
            renameProjectDraft: $renameProjectDraft,
            sidebarSavedSearchDraft: $sidebarSavedSearchDraft,
            subagentTranscript: $subagentTranscript,
            agentImportDialog: agentImportDialog,
            agentImportActions: actions.agentImport,
            onSelectThread: actions.onSelectThread,
            onSaveSettings: actions.onSaveSettings,
            onSaveKeyboardShortcuts: actions.onSaveKeyboardShortcuts,
            onStartTrustedRouterSignIn: actions.onStartTrustedRouterSignIn,
            onCommand: handleCommand,
            onCreateWorktreeThread: actions.onCreateWorktreeThread,
            onCreateWorktree: actions.onCreateWorktree,
            onCreateWorktreeBranch: actions.onCreateWorktreeBranch,
            onFinishWorktree: actions.onFinishWorktree,
            onRetryWorktreeChoices: retryWorktreeChoices,
            onOpenWorktree: actions.onOpenWorktree,
            onRemoveWorktree: actions.onRemoveWorktree,
            onRetryWorktreePrunePreview: retryWorktreePrunePreview,
            onPruneWorktrees: actions.onPruneWorktrees,
            onRenameThread: actions.onRenameThread,
            onRenameProject: actions.onRenameProject,
            onSaveSidebarSavedSearch: actions.onSaveSidebarSavedSearch,
            onToolCardAction: actions.onToolCardAction,
            onCopyTranscriptItem: actions.onCopyTranscriptItem
        )
    }

    private func attentionDigestOverlay(_ digest: AttentionDigestSurface) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { actions.onCloseAttentionDigest() }
                .quillCodeOwnedGestureTarget()
                .accessibilityLabel("Dismiss digest")
            QuillCodeAttentionDigestView(
                digest: digest,
                onClose: actions.onCloseAttentionDigest,
                onAcknowledge: { handleCommand(attentionCommand(.attentionAcknowledge)) },
                onDismiss: { handleCommand(attentionCommand(.attentionDismiss)) }
            )
        }
        .transition(.opacity)
    }

    private func attentionCommand(_ action: WorkspaceCommandAction) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(id: action.rawValue, title: action.rawValue)
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
            actions.onThreadAction(mutation)
        case let .renameProject(projectID, name):
            renameProjectDraft = QuillCodeProjectRenameDraft(projectID: projectID, name: name)
        case let .mutateProject(mutation):
            actions.onProjectAction(mutation)
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
            actions.onAddProjectRequested()
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
        case .presentNewWorktreeTask:
            worktreeDialogs.presentNewTask(environments: surface.worktreeEnvironments)
        case .presentCreateWorktree:
            worktreeDialogs.presentCreate()
        case .presentCreateWorktreeBranch:
            worktreeDialogs.presentCreateBranch()
        case .presentFinishWorktree:
            let projectName = surface.projects.items.first {
                $0.id == surface.projects.selectedProjectID
            }?.name ?? "Local"
            let cleanupOnly = surface.sidebar.items.first {
                $0.id == surface.sidebar.selectedThreadID
            }?.worktree?.location == .local
            worktreeDialogs.presentFinish(
                destinationName: projectName,
                isCleanupOnly: cleanupOnly
            )
        case .presentOpenWorktree:
            worktreeDialogs.presentOpen(loadChoices: actions.onListWorktreeChoices)
        case .presentRemoveWorktree:
            worktreeDialogs.presentRemove(loadChoices: actions.onListWorktreeChoices)
        case .presentPruneWorktrees:
            worktreeDialogs.presentPrune(loadPreview: actions.onPreviewWorktreePrune)
        case .openBrowserSession:
            actions.onOpenBrowserSession?()
        case .copyConversation:
            // Reuses the existing per-item copy closure (-> controller -> pasteboard),
            // so the whole-conversation export shares the same copy path and feedback.
            if let markdown = TranscriptMarkdownExporter.clipboardMarkdown(for: surface.transcript) {
                actions.onCopyTranscriptItem("conversation", markdown)
            }
        case .exportConversationMarkdown:
            if let markdown = TranscriptMarkdownExporter.exportableMarkdown(for: surface.transcript) {
                actions.onExportConversationMarkdown(surface.topBar.primaryTitle, markdown)
            }
        case let .presentSubagentTranscript(parentThreadID, runID, workerID):
            subagentTranscript = actions.onLoadSubagentTranscript(parentThreadID, runID, workerID)
        case let .dispatch(command, focusesComposer):
            actions.onCommand(command)
            if focusesComposer {
                DispatchQueue.main.async {
                    isComposerFocused = true
                }
            }
        }
    }

    private func retryWorktreeChoices(for sheet: QuillCodeWorktreeSheet) {
        worktreeDialogs.retryChoices(for: sheet, loadChoices: actions.onListWorktreeChoices)
    }

    private func retryWorktreePrunePreview() {
        worktreeDialogs.retryPrunePreview(loadPreview: actions.onPreviewWorktreePrune)
    }

    private func handleComposerSend() {
        guard case .slash(.workspaceCommand(let commandID), _) =
            WorkspaceComposerSubmissionPlanner.plan(
                draft: draft,
                hasAttachments: !surface.composer.attachments.isEmpty
            ),
            Self.composerPresentedCommandIDs.contains(commandID)
        else {
            actions.onSend()
            return
        }

        draft = ""
        switch commandID {
        case "search":
            searchQuery = ""
            isSearchPresented = true
        case "find-in-chat":
            isFindPresented = true
        case "settings":
            settingsDraft = QuillCodeSettingsDraft(settings: surface.settings)
            isSettingsPresented = true
        case "keyboard-shortcuts":
            isKeyboardShortcutsPresented = true
        case "command-palette":
            commandQuery = ""
            isCommandPalettePresented = true
        default:
            break
        }
    }

    private static let composerPresentedCommandIDs: Set<String> = [
        "find-in-chat",
        "command-palette",
        "keyboard-shortcuts",
        "search",
        "settings"
    ]
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

private extension WorkspaceTextScale {
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:
            .medium
        case .standard:
            .large
        case .large:
            .xLarge
        case .extraLarge:
            .xxLarge
        }
    }
}
