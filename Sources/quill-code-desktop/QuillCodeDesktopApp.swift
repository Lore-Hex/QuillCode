import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuillCodeApp

@main
struct QuillCodeDesktopApp: App {
    @StateObject private var controller: QuillCodeDesktopController

    init() {
        let controller = QuillCodeDesktopController()
        _controller = StateObject(wrappedValue: controller)

        guard let request = QuillCodeDesktopSmokeRequest(arguments: CommandLine.arguments) else {
            if let windowRequest = QuillCodeDesktopWindowSmokeRequest(arguments: CommandLine.arguments) {
                QuillCodeDesktopWindowSmokeLaunch.schedule(windowRequest)
            } else {
                QuillCodeDesktopMainWindowPresenter.shared.scheduleLaunch(controller: controller)
            }
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
            QuillCodeDesktopCommands()
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
            .quillCodeDesktopCommandNotifications(controller: controller)
            .fileImporter(
                isPresented: $controller.isProjectImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                controller.handleProjectImport(result)
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
            copiedTranscriptItemID: controller.copiedTranscriptItemID,
            onSend: controller.send,
            onRunTerminalCommand: controller.runTerminalCommand,
            onTerminalHistoryPrevious: controller.recallPreviousTerminalCommand,
            onTerminalHistoryNext: controller.recallNextTerminalCommand,
            onTerminalResize: controller.resizeTerminal,
            onTerminalSuspend: controller.suspendTerminal,
            onTerminalResume: controller.resumeTerminal,
            onOpenBrowserPreview: controller.openBrowserPreview,
            onOpenBrowserSession: controller.openBrowserSession,
            onAddBrowserComment: controller.addBrowserComment,
            onAddProjectRequested: controller.requestAddProject,
            onSelectThread: controller.selectThread,
            onThreadAction: controller.runThreadAction,
            onRenameThread: controller.renameThread,
            onSelectProject: controller.selectProject,
            onProjectAction: controller.runProjectAction,
            onRenameProject: controller.renameProject,
            onSetMode: controller.setMode,
            onSetModel: controller.setModel,
            onToggleModelFavorite: controller.toggleModelFavorite,
            onSaveSettings: controller.saveSettings,
            onStartTrustedRouterSignIn: controller.startTrustedRouterSignIn,
            onReviewAction: controller.runReviewAction,
            onPullRequestReviewThreadAction: controller.runPullRequestReviewThreadAction,
            onPullRequestReviewThreadReply: controller.runPullRequestReviewThreadReply,
            onPullRequestReviewDraftChange: controller.updatePullRequestReviewDraft,
            onCancelPullRequestReviewDraft: controller.cancelPullRequestReviewDraft,
            onSubmitPullRequestReviewDraft: controller.submitPullRequestReviewDraft,
            onToolCardAction: controller.runToolCardAction,
            onAddReviewComment: controller.addReviewComment,
            onCreateWorktree: controller.createWorktree,
            onListWorktreeChoices: controller.worktreeChoiceLoad,
            onOpenWorktree: controller.openWorktree,
            onRemoveWorktree: controller.removeWorktree,
            onPreviewWorktreePrune: controller.worktreePrunePreview,
            onPruneWorktrees: controller.pruneWorktrees,
            onCopyTranscriptItem: controller.copyTranscriptItem,
            onExportConversationMarkdown: controller.exportConversationMarkdown,
            onRevertTurn: controller.runTurnRevert,
            onMessageFeedback: controller.setMessageFeedback,
            onDeleteFollowUp: controller.deleteFollowUp,
            onSaveSidebarSavedSearch: controller.saveSidebarSavedSearch,
            onOpenAttentionDigest: controller.openAttentionDigest,
            onCloseAttentionDigest: controller.closeAttentionDigest,
            onCommand: controller.runCommand
        )
    }
}

private struct QuillCodeDesktopCommandNotifications: ViewModifier {
    @ObservedObject var controller: QuillCodeDesktopController
    @State private var observers: [NSObjectProtocol] = []

    func body(content: Content) -> some View {
        content
            .onAppear(perform: installObservers)
            .onDisappear(perform: removeObservers)
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        controller.installApprovalNotificationHandling()
        observers = [
            observe(.quillCodeNewChat) { $0.newChat() },
            observe(.quillCodeCycleMode) { $0.runWorkspaceCommand("cycle-mode") },
            observe(.quillCodeFocusComposer) { $0.runWorkspaceCommand("focus-composer") },
            observe(.quillCodeWorkspaceBack) { $0.runWorkspaceCommand("workspace-back") },
            observe(.quillCodeWorkspaceForward) { $0.runWorkspaceCommand("workspace-forward") },
            observe(.quillCodeToggleTerminal) { $0.toggleTerminal() },
            observe(.quillCodeToggleBrowser) { $0.toggleBrowser() },
            observe(.quillCodeBrowserBack) { $0.runWorkspaceCommand("browser-back") },
            observe(.quillCodeBrowserForward) { $0.runWorkspaceCommand("browser-forward") },
            observe(.quillCodeBrowserReload) { $0.runWorkspaceCommand("browser-reload") },
            observe(.quillCodeToggleExtensions) { $0.toggleExtensions() },
            observe(.quillCodeToggleMemories) { $0.toggleMemories() },
            observe(.quillCodeToggleActivity) { $0.toggleActivity() },
            observe(.quillCodeToggleAutomations) { $0.toggleAutomations() },
            observe(.quillCodeOpenProject) { $0.requestAddProject() },
            observe(.quillCodeCommandPalette) { $0.openCommandPalette() },
            observe(.quillCodeKeyboardShortcuts) { $0.openKeyboardShortcuts() },
            observe(.quillCodeOpenSettings) { $0.openSettings() },
            observe(.quillCodeStopAll) { $0.stopAll() },
            observe(.quillCodeRetryLastTurn) { $0.retryLastTurn() },
            observe(.quillCodeCopyConversation) { $0.copyCurrentConversation() },
            observe(.quillCodeExportConversationMarkdown) { $0.exportCurrentConversationMarkdown() }
        ]
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func observe(
        _ name: Notification.Name,
        perform action: @escaping @MainActor (QuillCodeDesktopController) -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak controller] _ in
            guard let controller else { return }
            Task { @MainActor in
                action(controller)
            }
        }
    }
}

private extension View {
    func quillCodeDesktopCommandNotifications(
        controller: QuillCodeDesktopController
    ) -> some View {
        modifier(QuillCodeDesktopCommandNotifications(controller: controller))
    }
}

@MainActor
private enum QuillCodeDesktopWindowSmokeLaunch {
    private static var observer: NSObjectProtocol?

    static func schedule(_ request: QuillCodeDesktopWindowSmokeRequest) {
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
                await QuillCodeDesktopWindowSmokeRunner.runAndExit(request)
            }
        }
    }
}
