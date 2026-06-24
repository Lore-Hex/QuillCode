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
    public var onToolCardAction: (ToolCardActionSurface) -> Void
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
        onToolCardAction: @escaping (ToolCardActionSurface) -> Void = { _ in },
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
        self.onToolCardAction = onToolCardAction
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
                    onOpenBrowserPreview: onOpenBrowserPreview,
                    onOpenBrowserSession: onOpenBrowserSession,
                    onAddBrowserComment: onAddBrowserComment,
                    onReviewAction: onReviewAction,
                    onToolCardAction: onToolCardAction,
                    onAddReviewComment: onAddReviewComment,
                    onCopyTranscriptItem: onCopyTranscriptItem,
                    onMessageFeedback: onMessageFeedback,
                    onCommand: handleCommand
                )
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
        .quillCodeWorkspaceSheets(
            surface: surface,
            isSearchPresented: $isSearchPresented,
            searchQuery: $searchQuery,
            isCommandPalettePresented: $isCommandPalettePresented,
            commandQuery: $commandQuery,
            isSettingsPresented: $isSettingsPresented,
            settingsDraft: $settingsDraft,
            isKeyboardShortcutsPresented: $isKeyboardShortcutsPresented,
            worktreeSheet: $worktreeSheet,
            createWorktreeDraft: $createWorktreeDraft,
            removeWorktreeDraft: $removeWorktreeDraft,
            renameThreadDraft: $renameThreadDraft,
            renameProjectDraft: $renameProjectDraft,
            onSelectThread: onSelectThread,
            onSaveSettings: onSaveSettings,
            onStartTrustedRouterSignIn: onStartTrustedRouterSignIn,
            onCommand: handleCommand,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRenameThread: onRenameThread,
            onRenameProject: onRenameProject
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
        case let .renameThread(threadID, title):
            renameThreadDraft = QuillCodeThreadRenameDraft(threadID: threadID, title: title)
        case let .renameProject(projectID, name):
            renameProjectDraft = QuillCodeProjectRenameDraft(projectID: projectID, name: name)
        case .presentCreateWorktree:
            createWorktreeDraft = QuillCodeWorktreeCreateDraft()
            worktreeSheet = .create
        case .presentRemoveWorktree:
            removeWorktreeDraft = QuillCodeWorktreeRemoveDraft()
            worktreeSheet = .remove
        case .openBrowserSession:
            onOpenBrowserSession?()
        case let .dispatch(command, focusesComposer):
            onCommand(command)
            if focusesComposer {
                DispatchQueue.main.async {
                    isComposerFocused = true
                }
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
