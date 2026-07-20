import SwiftUI
import QuillCodeCore
import QuillCodeTools

struct QuillCodeWorkspaceMainPaneView: View {
    var surface: WorkspaceSurface
    @Binding var draft: String
    @Binding var terminalDraft: String
    @Binding var browserAddressDraft: String
    @Binding var isModelPickerPresented: Bool
    @Binding var isFindPresented: Bool
    @Binding var findQuery: String
    @Binding var activeFindIndex: Int
    var isComposerFocused: FocusState<Bool>.Binding
    var copiedTranscriptItemID: String?
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void
    var onSend: () -> Void
    var onAddImagesRequested: () -> Void = {}
    var onRemoveImage: (UUID) -> Void = { _ in }
    var onRunTerminalCommand: () -> Void
    var onTerminalHistoryPrevious: () -> Void
    var onTerminalHistoryNext: () -> Void
    var onTerminalResize: (TerminalWindowSize) -> Void = { _ in }
    var onTerminalMouseInput: (TerminalMouseInputRequest) -> Void = { _ in }
    var onTerminalKeyboardInput: (TerminalKeyboardInputRequest) -> Void = { _ in }
    var onTerminalSuspend: () -> Void = {}
    var onTerminalResume: () -> Void = {}
    var onOpenBrowserPreview: () -> Void
    var onOpenBrowserSession: (() -> Void)?
    var onAddBrowserComment: (String) -> Void
    var onReviewScopeChange: (WorkspaceReviewSelection) -> Void
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onPullRequestReviewThreadReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void
    var onPullRequestReviewDraftChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    var onCancelPullRequestReviewDraft: () -> Void
    var onSubmitPullRequestReviewDraft: () -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onRevertTurn: (UUID) -> Void = { _ in }
    var onDeleteFollowUp: (UUID) -> Void = { _ in }
    var onStartTrustedRouterSignIn: () -> Void = {}
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if surface.isConfidential {
                    QuillCodeConfidentialBannerView()
                }
                if let sideConversation = surface.sideConversation {
                    QuillCodeSideConversationView(
                        sideConversation: sideConversation,
                        onCommand: onCommand
                    )
                }
                if surface.automations.isVisible {
                    QuillCodeAutomationsPaneView(
                        automations: surface.automations,
                        onClose: { runCommand(id: "toggle-automations") },
                        onCommand: onCommand
                    )
                    Divider()
                }
                if !surface.automations.isVisible || !surface.transcript.timelineItems.isEmpty {
                    QuillCodeTranscriptView(
                        transcript: surface.transcript,
                        threadID: surface.sidebar.selectedThreadID,
                        contextBanner: surface.contextBanner,
                        runtimeIssue: surface.runtimeIssue,
                        review: surface.review,
                        retryLastTurnCommand: surface.commands.first { $0.id == "retry-last-turn" && $0.isEnabled },
                        isFindPresented: $isFindPresented,
                        findQuery: $findQuery,
                        activeFindIndex: $activeFindIndex,
                        copiedTranscriptItemID: copiedTranscriptItemID,
                        onContextCommand: onCommand,
                        onRuntimeIssueAction: runtimeIssueAction(for: surface.runtimeIssue),
                        onCloseReview: { runCommand(id: "toggle-review-panel") },
                        onReviewScopeChange: onReviewScopeChange,
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
                        onUseMessageAsDraft: useMessageAsDraft,
                        onSubmitStarterAction: submitStarterAction,
                        connectPrompt: TranscriptConnectPrompt.make(
                            hasStoredAPIKey: surface.settings.hasStoredAPIKey,
                            signInURL: surface.settings.signInURL
                        ),
                        onStartTrustedRouterSignIn: onStartTrustedRouterSignIn
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
                        onOpenSession: onOpenBrowserSession,
                        onAddComment: onAddBrowserComment,
                        onCommand: runCommand(id:)
                    )
                }
                if surface.extensions.isVisible {
                    Divider()
                    QuillCodeExtensionsPaneView(
                        extensions: surface.extensions,
                        onClose: { runCommand(id: "toggle-extensions") },
                        onCommand: onCommand
                    )
                }
                if surface.memories.isVisible {
                    Divider()
                    QuillCodeMemoriesPaneView(
                        memories: surface.memories,
                        onClose: { runCommand(id: "toggle-memories") }
                    ) { commandID in
                        if let command = surface.commands.first(where: { $0.id == commandID }) {
                            onCommand(command)
                        } else if commandID.hasPrefix("memory-edit:")
                            || commandID.hasPrefix("memory-delete:") {
                            onCommand(WorkspaceCommandSurface(
                                id: commandID,
                                title: commandID.hasPrefix("memory-edit:") ? "Edit memory" : "Forget memory",
                                category: WorkspaceCommandPalette.memoriesCategory,
                                keywords: ["memory", "edit", "forget", "delete"]
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
                        onSuspend: onTerminalSuspend,
                        onResume: onTerminalResume,
                        onClear: { runCommand(id: "terminal-clear") },
                        onHistoryPrevious: onTerminalHistoryPrevious,
                        onHistoryNext: onTerminalHistoryNext,
                        onResize: onTerminalResize,
                        onMouseInput: onTerminalMouseInput,
                        onKeyboardInput: onTerminalKeyboardInput
                    )
                }
                Divider()
                QuillCodeComposerView(
                    composer: surface.composer,
                    topBar: surface.topBar,
                    fileMentionIndex: surface.fileMentionIndex,
                    changedFilePaths: surface.changedFilePaths,
                    sentMessageHistory: surface.composer.sentMessageHistory,
                    draft: $draft,
                    isModelPickerPresented: $isModelPickerPresented,
                    isFocused: isComposerFocused,
                    onSetMode: onSetMode,
                    onSetModel: onSetModel,
                    onToggleModelFavorite: onToggleModelFavorite,
                    onSend: onSend,
                    onAddImagesRequested: onAddImagesRequested,
                    onRemoveImage: onRemoveImage,
                    onStop: stopActiveRun,
                    onDeleteFollowUp: onDeleteFollowUp
                )
            }
            if surface.activity.isVisible {
                Divider()
                QuillCodeActivityPaneView(
                    activity: surface.activity,
                    onClose: { runCommand(id: "toggle-activity") },
                    onCommand: { commandID in
                        onCommand(WorkspaceCommandSurface(
                            id: commandID,
                            title: "Toggle activity section",
                            category: WorkspaceCommandPalette.workspaceCategory,
                            keywords: ["activity", "task", "collapse", "expand"]
                        ))
                    }
                )
                    .frame(width: 320)
            }
        }
        // One switch flips the whole pane into the violet confidential ramp — the transcript,
        // composer, banner, and bubbles all read this instead of threading a flag through inits.
        .environment(\.quillCodeConfidentialAppearance, surface.isConfidential)
    }

    private func runCommand(id: String) {
        if let command = surface.commands.first(where: { $0.id == id }) {
            onCommand(command)
            return
        }
        guard WorkspaceCommandRoutingCatalog.isDispatchable(id) else { return }
        onCommand(WorkspaceCommandSurface(
            id: id,
            title: browserCommandTitle(for: id),
            category: WorkspaceCommandPalette.workspaceCategory,
            keywords: ["browser", "tab", "preview", "web"]
        ))
    }

    private func browserCommandTitle(for id: String) -> String {
        if id == "browser-tab-new" {
            return "Browser: New tab"
        }
        if id.hasPrefix("browser-tab-select:") {
            return "Browser: Select tab"
        }
        if id.hasPrefix("browser-tab-close:") {
            return "Browser: Close tab"
        }
        return id
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
            isComposerFocused.wrappedValue = true
        }
    }

    private func submitStarterAction(_ text: String) {
        // Prefill + focus, don't auto-fire: an example prompt on a project the user hasn't described
        // should be editable (tweak scope, switch mode, add an @file) before they press Return — the
        // Codex/Claude-Code idiom. Auto-sending a canned prompt burns a turn with no chance to edit.
        draft = text
        DispatchQueue.main.async {
            isComposerFocused.wrappedValue = true
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
                onCommand(command)
            }
        }
    }
}
