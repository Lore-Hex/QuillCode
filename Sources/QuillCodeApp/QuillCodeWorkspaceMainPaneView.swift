import SwiftUI
import QuillCodeCore

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
    var onRunTerminalCommand: () -> Void
    var onTerminalHistoryPrevious: () -> Void
    var onTerminalHistoryNext: () -> Void
    var onOpenBrowserPreview: () -> Void
    var onOpenBrowserSession: (() -> Void)?
    var onAddBrowserComment: (String) -> Void
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onMessageFeedback: (UUID, MessageFeedbackValue) -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if surface.automations.isVisible {
                    QuillCodeAutomationsPaneView(
                        automations: surface.automations,
                        onCommand: onCommand
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
                        onContextCommand: onCommand,
                        onRuntimeIssueAction: runtimeIssueAction(for: surface.runtimeIssue),
                        onReviewAction: onReviewAction,
                        onPullRequestReviewThreadAction: onPullRequestReviewThreadAction,
                        onToolCardAction: onToolCardAction,
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
                        onOpenSession: onOpenBrowserSession,
                        onAddComment: onAddBrowserComment,
                        onCommand: runCommand(id:)
                    )
                }
                if surface.extensions.isVisible {
                    Divider()
                    QuillCodeExtensionsPaneView(
                        extensions: surface.extensions,
                        onCommand: onCommand
                    )
                }
                if surface.memories.isVisible {
                    Divider()
                    QuillCodeMemoriesPaneView(memories: surface.memories) { commandID in
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
                        onClear: { runCommand(id: "terminal-clear") },
                        onHistoryPrevious: onTerminalHistoryPrevious,
                        onHistoryNext: onTerminalHistoryNext
                    )
                }
                Divider()
                QuillCodeComposerView(
                    composer: surface.composer,
                    topBar: surface.topBar,
                    draft: $draft,
                    isModelPickerPresented: $isModelPickerPresented,
                    isFocused: isComposerFocused,
                    onSetMode: onSetMode,
                    onSetModel: onSetModel,
                    onToggleModelFavorite: onToggleModelFavorite,
                    onSend: onSend,
                    onStop: stopActiveRun
                )
            }
            if surface.activity.isVisible {
                Divider()
                QuillCodeActivityPaneView(activity: surface.activity) { commandID in
                    onCommand(WorkspaceCommandSurface(
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

    private func runCommand(id: String) {
        guard let command = surface.commands.first(where: { $0.id == id }) else { return }
        onCommand(command)
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
