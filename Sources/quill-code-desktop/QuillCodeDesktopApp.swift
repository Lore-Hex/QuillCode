import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuillCodeApp

@main
struct QuillCodeDesktopApp: App {
    @StateObject private var controller: QuillCodeDesktopController

    init() {
        if let windowRequest = QuillCodeDesktopWindowSmokeRequest(arguments: CommandLine.arguments) {
            let workspaceRoot = QuillCodeDesktopWindowSmokeWorkspaceRoot(request: windowRequest)
            let controller = workspaceRoot.makeController()
            _controller = StateObject(wrappedValue: controller)
            QuillCodeDesktopWindowSmokeLaunch.schedule(
                windowRequest,
                controller: controller,
                workspaceRoot: workspaceRoot
            )
            return
        }

        let controller = QuillCodeDesktopController()
        _controller = StateObject(wrappedValue: controller)

        guard let request = QuillCodeDesktopSmokeRequest(arguments: CommandLine.arguments) else {
            QuillCodeDesktopMainWindowPresenter.shared.scheduleLaunch(controller: controller)
            return
        }
        Task { @MainActor in
            await QuillCodeDesktopSmokeRunner.runAndExit(request)
        }
    }

    var body: some Scene {
        WindowGroup("QuillCode") {
            QuillCodeDesktopRootView(controller: controller)
        }
        .defaultSize(width: 1280, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            QuillCodeDesktopCommands(
                commands: controller.surface.commands,
                shortcutProfile: WorkspaceShortcutRegistry.profile(
                    preferences: controller.surface.settings.keyboardShortcuts
                ),
                onCommand: { controller.runCommand(commandID: $0) }
            )
        }
        MenuBarExtra {
            QuillCodeMenuBarView(
                surface: controller.surface,
                onNewChat: controller.newChat,
                onOpenProject: controller.requestAddProject,
                onCommandPalette: controller.openCommandPalette,
                onKeyboardShortcuts: controller.openKeyboardShortcuts,
                onSettings: controller.openSettings,
                onToggleTerminal: controller.toggleTerminal,
                onToggleBrowser: controller.toggleBrowser,
                onOpenBrowserSession: controller.openBrowserSession,
                onToggleExtensions: controller.toggleExtensions,
                onStopWorkflowRecording: controller.stopWorkflowRecording,
                onToggleMemories: controller.toggleMemories,
                onStopAll: controller.stopAll,
                onDisconnectAll: controller.disconnectAll,
                onComputerUseSetup: controller.openSettings,
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        } label: {
            Image(nsImage: QuillCodeMenuBarIcon.image)
                .accessibilityLabel("QuillCode")
        }
    }
}

struct QuillCodeDesktopRootView: View {
    @ObservedObject var controller: QuillCodeDesktopController

    var body: some View {
        workspaceContent
            .quillCodeDesktopCommandBindings(controller: controller)
            .fileImporter(
                isPresented: $controller.isProjectImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                controller.handleProjectImport(result)
            }
            .fileImporter(
                isPresented: $controller.isImageImporterPresented,
                allowedContentTypes: [.png, .jpeg, .gif, .webP],
                allowsMultipleSelection: true
            ) { result in
                controller.handleImageImport(result)
            }
            .task {
                await controller.refreshModelCatalog()
            }
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

private struct QuillCodeDesktopCommandBindings: ViewModifier {
    @ObservedObject var controller: QuillCodeDesktopController
    @State private var shortcutMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: installBindings)
            .onDisappear(perform: removeBindings)
            .onChange(of: controller.surface.settings.keyboardShortcuts) { _, _ in
                installShortcutMonitor()
            }
    }

    private func installBindings() {
        controller.installApprovalNotificationHandling()
        installShortcutMonitor()
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

@MainActor
private enum QuillCodeDesktopWindowSmokeLaunch {
    private static var observer: NSObjectProtocol?

    static func schedule(
        _ request: QuillCodeDesktopWindowSmokeRequest,
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopWindowSmokeWorkspaceRoot
    ) {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    Self.observer = nil
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                await QuillCodeDesktopWindowSmokeRunner.runAndExit(
                    request,
                    controller: controller,
                    workspaceRoot: workspaceRoot
                )
            }
        }
    }
}
