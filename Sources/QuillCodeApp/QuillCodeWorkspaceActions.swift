import Foundation
import QuillCodeCore
import QuillCodeTools

public struct QuillCodeWorkspaceActions {
    let onSend: () -> Void
    let onAddImagesRequested: () -> Void
    let onRemoveImage: (UUID) -> Void
    let onRunTerminalCommand: () -> Void
    let onTerminalHistoryPrevious: () -> Void
    let onTerminalHistoryNext: () -> Void
    let onTerminalResize: (TerminalWindowSize) -> Void
    let onTerminalMouseInput: (TerminalMouseInputRequest) -> Void
    let onTerminalSuspend: () -> Void
    let onTerminalResume: () -> Void
    let onOpenBrowserPreview: () -> Void
    let onOpenBrowserSession: (() -> Void)?
    let onAddBrowserComment: (String) -> Void
    let onAddProjectRequested: () -> Void
    let onSelectThread: (UUID) -> Void
    let onThreadAction: (WorkspaceThreadRowMutation) -> Void
    let onRenameThread: (UUID, String) -> Void
    let onSelectProject: (UUID?) -> Void
    let onProjectAction: (WorkspaceProjectRowMutation) -> Void
    let onMoveProjectBefore: (UUID, UUID) -> Bool
    let onMoveProjectToBottom: (UUID) -> Bool
    let onRenameProject: (UUID, String) -> Void
    let onSetMode: (AgentMode) -> Void
    let onSetModel: (String) -> Void
    let onToggleModelFavorite: (String) -> Void
    let onSaveSettings: (WorkspaceSettingsUpdate) -> Void
    let onStartTrustedRouterSignIn: () -> Void
    let onReviewAction: (WorkspaceReviewActionSurface) -> Void
    let onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    let onPullRequestReviewThreadReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void
    let onPullRequestReviewDraftChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    let onCancelPullRequestReviewDraft: () -> Void
    let onSubmitPullRequestReviewDraft: () -> Void
    let onToolCardAction: (ToolCardActionSurface) -> Void
    let onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    let onCreateWorktree: (WorkspaceWorktreeCreateRequest) -> Void
    let onListWorktreeChoices: () async -> WorkspaceWorktreeChoiceLoad
    let onOpenWorktree: (WorkspaceWorktreeOpenRequest) -> Void
    let onRemoveWorktree: (WorkspaceWorktreeRemoveRequest) -> Void
    let onPreviewWorktreePrune: () async -> WorkspaceWorktreePrunePreview
    let onPruneWorktrees: (WorkspaceWorktreePruneRequest) -> Void
    let onCopyTranscriptItem: (String, String) -> Void
    let onExportConversationMarkdown: (String, String) -> Void
    let onRevertTurn: (UUID) -> Void
    let onDeleteFollowUp: (UUID) -> Void
    let onSaveSidebarSavedSearch: (String, String) -> Void
    let onOpenAttentionDigest: (UUID) -> Void
    let onCloseAttentionDigest: () -> Void
    let onCommand: (WorkspaceCommandSurface) -> Void

    public init(
        onSend: @escaping () -> Void,
        onAddImagesRequested: @escaping () -> Void = {},
        onRemoveImage: @escaping (UUID) -> Void = { _ in },
        onRunTerminalCommand: @escaping () -> Void,
        onTerminalHistoryPrevious: @escaping () -> Void = {},
        onTerminalHistoryNext: @escaping () -> Void = {},
        onTerminalResize: @escaping (TerminalWindowSize) -> Void = { _ in },
        onTerminalMouseInput: @escaping (TerminalMouseInputRequest) -> Void = { _ in },
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
        onDeleteFollowUp: @escaping (UUID) -> Void = { _ in },
        onSaveSidebarSavedSearch: @escaping (String, String) -> Void = { _, _ in },
        onOpenAttentionDigest: @escaping (UUID) -> Void = { _ in },
        onCloseAttentionDigest: @escaping () -> Void = {},
        onCommand: @escaping (WorkspaceCommandSurface) -> Void
    ) {
        self.onSend = onSend
        self.onAddImagesRequested = onAddImagesRequested
        self.onRemoveImage = onRemoveImage
        self.onRunTerminalCommand = onRunTerminalCommand
        self.onTerminalHistoryPrevious = onTerminalHistoryPrevious
        self.onTerminalHistoryNext = onTerminalHistoryNext
        self.onTerminalResize = onTerminalResize
        self.onTerminalMouseInput = onTerminalMouseInput
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
        self.onMoveProjectBefore = onMoveProjectBefore
        self.onMoveProjectToBottom = onMoveProjectToBottom
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
        self.onDeleteFollowUp = onDeleteFollowUp
        self.onSaveSidebarSavedSearch = onSaveSidebarSavedSearch
        self.onOpenAttentionDigest = onOpenAttentionDigest
        self.onCloseAttentionDigest = onCloseAttentionDigest
        self.onCommand = onCommand
    }
}
