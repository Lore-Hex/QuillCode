import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuillCodeApp

@main
struct QuillCodeDesktopApp: App {
    @StateObject private var controller = QuillCodeDesktopController()

    init() {
        guard let request = QuillCodeDesktopSmokeRequest(arguments: CommandLine.arguments) else {
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
            Label("QuillCode", systemImage: "q.circle.fill")
        }
    }
}

struct QuillCodeDesktopRootView: View {
    @ObservedObject var controller: QuillCodeDesktopController

    var body: some View {
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
            onMessageFeedback: controller.setMessageFeedback,
            onCommand: controller.runCommand
        )
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeNewChat)) { _ in
            controller.newChat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeToggleTerminal)) { _ in
            controller.toggleTerminal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeToggleBrowser)) { _ in
            controller.toggleBrowser()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeBrowserBack)) { _ in
            controller.runWorkspaceCommand("browser-back")
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeBrowserForward)) { _ in
            controller.runWorkspaceCommand("browser-forward")
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeBrowserReload)) { _ in
            controller.runWorkspaceCommand("browser-reload")
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeToggleExtensions)) { _ in
            controller.toggleExtensions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeToggleMemories)) { _ in
            controller.toggleMemories()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeOpenProject)) { _ in
            controller.requestAddProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeCommandPalette)) { _ in
            controller.openCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeKeyboardShortcuts)) { _ in
            controller.openKeyboardShortcuts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeOpenSettings)) { _ in
            controller.openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeStopAll)) { _ in
            controller.stopAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeRetryLastTurn)) { _ in
            controller.retryLastTurn()
        }
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
}
