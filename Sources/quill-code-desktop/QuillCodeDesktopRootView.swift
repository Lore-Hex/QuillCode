import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuillCodeApp

struct QuillCodeDesktopRootView: View {
    @ObservedObject var controller: QuillCodeDesktopController
    @State private var unexpectedExit: QuillCodeDesktopUnexpectedExit?

    init(controller: QuillCodeDesktopController) {
        self.controller = controller
        _unexpectedExit = State(
            initialValue: controller.launchLifecycleController?.takeUnexpectedExit()
        )
    }

    var body: some View {
        workspaceContent
            .preferredColorScheme(.dark)
            .quillCodeDesktopCommandBindings(controller: controller)
            .modifier(QuillCodeDesktopDistributionPresentation(
                installationLocationController: controller.installationLocationController,
                updateController: controller.updateController
            ))
            .fileImporter(
                isPresented: $controller.isProjectImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                controller.handleProjectImport(result)
            }
            .background {
                Color.clear
                    .fileImporter(
                        isPresented: $controller.isImageImporterPresented,
                        allowedContentTypes: [.png, .jpeg, .gif, .webP],
                        allowsMultipleSelection: true
                    ) { result in
                        controller.handleImageImport(result)
                    }
            }
            .task {
                await Task.yield()
                controller.completeStartupIfAllowed()
            }
            .alert(
                unexpectedExitTitle,
                isPresented: unexpectedExitBinding,
                presenting: unexpectedExit
            ) { incident in
                if incident.requiresRecoveryStartup {
                    Button("Keep Background Work Paused") {
                        continueWithAutomaticWorkspaceServicesPaused()
                    }
                    .keyboardShortcut(.defaultAction)
                    .quillCodePlatformMenuItemTarget(
                        reason: "macOS owns alert action geometry."
                    )
                    .accessibilityIdentifier("quillcode-startup-recovery-keep-paused")
                    Button("Resume Background Work") {
                        controller.resumeAutomaticWorkspaceServices()
                        unexpectedExit = nil
                    }
                    .quillCodePlatformMenuItemTarget(
                        reason: "macOS owns alert action geometry."
                    )
                    .accessibilityIdentifier("quillcode-startup-recovery-resume")
                } else {
                    Button("Continue") {
                        unexpectedExit = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .quillCodePlatformMenuItemTarget(
                        reason: "macOS owns alert action geometry."
                    )
                    .accessibilityIdentifier("quillcode-unexpected-exit-continue")
                }
                Button("Report Issue...") {
                    reportUnexpectedExit(incident)
                }
                .quillCodePlatformMenuItemTarget(
                    reason: "macOS owns alert action geometry."
                )
                .accessibilityIdentifier("quillcode-unexpected-exit-report")
            } message: { incident in
                Text(incident.userMessage)
            }
    }

    private var unexpectedExitBinding: Binding<Bool> {
        Binding(
            get: { unexpectedExit != nil },
            set: { isPresented in
                if !isPresented {
                    continueWithAutomaticWorkspaceServicesPaused()
                }
            }
        )
    }

    private var unexpectedExitTitle: String {
        unexpectedExit?.requiresRecoveryStartup == true
            ? "Quill Cowork opened in recovery mode"
            : "Quill Cowork closed unexpectedly"
    }

    private func continueWithAutomaticWorkspaceServicesPaused() {
        if unexpectedExit?.requiresRecoveryStartup == true {
            controller.continueWithAutomaticWorkspaceServicesPaused()
        }
        unexpectedExit = nil
    }

    private func reportUnexpectedExit(_ incident: QuillCodeDesktopUnexpectedExit) {
        if incident.requiresRecoveryStartup {
            controller.continueWithAutomaticWorkspaceServicesPaused()
        }
        unexpectedExit = nil
        QuillCodeDesktopIssueReporter.open(
            configuration: controller.updateController.configuration,
            incident: incident
        )
    }

    private var workspaceContent: some View {
        QuillCodeWorkspaceView(
            surface: controller.surface,
            draft: $controller.draft,
            terminalDraft: $controller.terminalDraft,
            browserAddressDraft: $controller.browserAddressDraft,
            isCommandPalettePresented: $controller.isCommandPalettePresented,
            isSettingsPresented: $controller.isSettingsPresented,
            isKeyboardShortcutsPresented: $controller.isKeyboardShortcutsPresented,
            isSearchPresented: $controller.isSearchPresented,
            isFindPresented: $controller.isFindPresented,
            isModelPickerPresented: $controller.isModelPickerPresented,
            copiedTranscriptItemID: controller.copiedTranscriptItemID,
            onSend: controller.send,
            onAddImagesRequested: controller.requestAddImages,
            onRemoveImage: controller.removeComposerImage,
            onRunTerminalCommand: controller.runTerminalCommand,
            onTerminalHistoryPrevious: controller.recallPreviousTerminalCommand,
            onTerminalHistoryNext: controller.recallNextTerminalCommand,
            onTerminalResize: controller.resizeTerminal,
            onTerminalMouseInput: controller.sendTerminalMouseInput,
            onTerminalKeyboardInput: controller.sendTerminalKeyboardInput,
            onTerminalSuspend: controller.suspendTerminal,
            onTerminalResume: controller.resumeTerminal,
            onOpenBrowserPreview: controller.openBrowserPreview,
            onOpenBrowserSession: controller.openBrowserSession,
            onAddBrowserComment: controller.addBrowserComment,
            onAddProjectRequested: controller.requestAddProject,
            onDiscoverSSHHosts: controller.discoverSSHHosts,
            onRegisterSSHProject: controller.registerSSHProject,
            onSelectThread: controller.selectThread,
            onThreadAction: controller.runThreadAction,
            onRenameThread: controller.renameThread,
            onSelectProject: controller.selectProject,
            onProjectAction: controller.runProjectAction,
            onMoveProjectBefore: controller.moveProject,
            onMoveProjectToBottom: controller.moveProjectToBottom,
            onRenameProject: controller.renameProject,
            onSetMode: controller.setMode,
            onSetModel: controller.setModel,
            onToggleModelFavorite: controller.toggleModelFavorite,
            onSaveSettings: controller.saveSettings,
            onSetRunSpendLimit: controller.setRunSpendLimit,
            onSaveKeyboardShortcuts: controller.saveKeyboardShortcuts,
            onStartTrustedRouterSignIn: controller.startTrustedRouterSignIn,
            agentImportActions: QuillCodeAgentImportActions(
                discover: controller.discoverAgentImport,
                perform: controller.performAgentImport
            ),
            onDismissCodeReview: controller.dismissCodeReview,
            onRunCodeReview: controller.runCodeReview,
            onReviewScopeChange: controller.runReviewScopeChange,
            onReviewAction: controller.runReviewAction,
            onPullRequestReviewThreadAction: controller.runPullRequestReviewThreadAction,
            onPullRequestReviewThreadReply: controller.runPullRequestReviewThreadReply,
            onPullRequestReviewDraftChange: controller.updatePullRequestReviewDraft,
            onCancelPullRequestReviewDraft: controller.cancelPullRequestReviewDraft,
            onSubmitPullRequestReviewDraft: controller.submitPullRequestReviewDraft,
            onToolCardAction: controller.runToolCardAction,
            onAddReviewComment: controller.addReviewComment,
            onCreateWorktreeThread: controller.createWorktreeThread,
            onCreateWorktree: controller.createWorktree,
            onCreateWorktreeBranch: controller.createWorktreeBranch,
            onFinishWorktree: controller.finishWorktree,
            onListWorktreeChoices: controller.worktreeChoiceLoad,
            onOpenWorktree: controller.openWorktree,
            onRemoveWorktree: controller.removeWorktree,
            onPreviewWorktreePrune: controller.worktreePrunePreview,
            onPruneWorktrees: controller.pruneWorktrees,
            onCopyTranscriptItem: controller.copyTranscriptItem,
            onExportConversationMarkdown: controller.exportConversationMarkdown,
            onRevertTurn: controller.runTurnRevert,
            onDeleteFollowUp: controller.deleteFollowUp,
            onSaveSidebarSavedSearch: controller.saveSidebarSavedSearch,
            onOpenAttentionDigest: controller.openAttentionDigest,
            onCloseAttentionDigest: controller.closeAttentionDigest,
            onLoadSubagentTranscript: controller.loadSubagentTranscript,
            onCommand: controller.runCommand
        )
    }
}

private struct QuillCodeDesktopDistributionPresentation: ViewModifier {
    @ObservedObject var installationLocationController: QuillCodeDesktopInstallationLocationController
    @ObservedObject var updateController: QuillCodeDesktopUpdateController

    func body(content: Content) -> some View {
        content.sheet(isPresented: presentationBinding) {
            if installationLocationController.isPresented {
                QuillCodeDesktopInstallationLocationView(
                    controller: installationLocationController
                )
            } else {
                QuillCodeDesktopUpdateView(
                    controller: updateController,
                    onMoveToApplications: {
                        guard !installationLocationController.presentForUpdate() else { return }
                        updateController.openManualInstaller()
                    }
                )
            }
        }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: {
                installationLocationController.isPresented || updateController.isPresented
            },
            set: { isPresented in
                guard !isPresented else { return }
                if installationLocationController.isPresented {
                    installationLocationController.dismiss()
                } else {
                    updateController.dismiss()
                }
            }
        )
    }
}

private struct QuillCodeDesktopCommandBindings: ViewModifier {
    @ObservedObject var controller: QuillCodeDesktopController
    @State private var shortcutMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: installShortcutMonitor)
            .onDisappear(perform: removeBindings)
            .onChange(of: controller.surface.settings.keyboardShortcuts) { _, _ in
                installShortcutMonitor()
            }
    }

    private func removeBindings() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func installShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        let profile = WorkspaceShortcutRegistry.profile(
            preferences: controller.surface.settings.keyboardShortcuts
        )
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let shortcutEvent = QuillCodeDesktopShortcutEvent(event),
                  let commandID = QuillCodeSecondaryShortcutResolver.commandID(
                    for: shortcutEvent,
                    profile: profile
                  )
            else { return event }
            controller.runCommand(commandID: commandID)
            return nil
        }
    }
}

private extension View {
    func quillCodeDesktopCommandBindings(
        controller: QuillCodeDesktopController
    ) -> some View {
        modifier(QuillCodeDesktopCommandBindings(controller: controller))
    }
}
