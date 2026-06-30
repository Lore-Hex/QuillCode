import Foundation
import SwiftUI
import QuillCodeApp
import QuillCodeCore

@MainActor
final class QuillCodeDesktopController: ObservableObject {
    @Published var surface: WorkspaceSurface
    @Published var draft: String
    @Published var terminalDraft: String
    @Published var browserAddressDraft: String
    @Published var isCommandPalettePresented = false
    @Published var isSettingsPresented = false
    @Published var isKeyboardShortcutsPresented = false
    @Published var isProjectImporterPresented = false
    @Published var copiedTranscriptItemID: String?

    private let model: QuillCodeWorkspaceModel
    private let bootstrap: QuillCodeWorkspaceBootstrap
    private let computerUseCoordinator: QuillCodeDesktopComputerUseCoordinator
    private let activeWorkCoordinator: QuillCodeDesktopActiveWorkCoordinator
    private let browserCoordinator: QuillCodeDesktopBrowserCoordinator
    private let automationCoordinator: QuillCodeDesktopAutomationCoordinator
    private let automationNotifier: any QuillCodeAutomationNotifying
    private let workspaceRoot: URL
    private let navigationCoordinator: QuillCodeDesktopNavigationCoordinator
    private let commandCoordinator: QuillCodeDesktopCommandCoordinator
    private let signInCoordinator: QuillCodeDesktopSignInCoordinator
    private let settingsCoordinator: QuillCodeDesktopSettingsCoordinator
    private let composerCoordinator: QuillCodeDesktopComposerCoordinator
    private let copyCoordinator: QuillCodeDesktopCopyCoordinator
    private let projectImportCoordinator: QuillCodeDesktopProjectImportCoordinator
    private let modelStateCoordinator: QuillCodeDesktopModelStateCoordinator
    private let paneCoordinator: QuillCodeDesktopPaneCoordinator
    private let workspaceActionCoordinator: QuillCodeDesktopWorkspaceActionCoordinator
    private let terminalCoordinator: QuillCodeDesktopTerminalCoordinator
    private let worktreeCoordinator: QuillCodeDesktopWorktreeCoordinator
    private let tasks = QuillCodeDesktopTaskCoordinator()

    init(
        bootstrap: QuillCodeWorkspaceBootstrap = QuillCodeWorkspaceBootstrap(),
        browserPageFetcher: any BrowserPageFetching = URLSessionBrowserPageFetcher(),
        browserLiveDOMCapturer: (any BrowserLiveDOMCapturing)? = DesktopBrowserLiveDOMCapturer(),
        browserSessionPresenter: any DesktopBrowserSessionPresenting = DesktopBrowserSessionPresenter(),
        automationNotifier: any QuillCodeAutomationNotifying = MacAutomationNotifier(),
        workspaceRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) {
        self.bootstrap = bootstrap
        self.computerUseCoordinator = QuillCodeDesktopComputerUseCoordinator()
        self.activeWorkCoordinator = QuillCodeDesktopActiveWorkCoordinator()
        self.browserCoordinator = QuillCodeDesktopBrowserCoordinator(
            pageFetcher: browserPageFetcher,
            liveDOMCapturer: browserLiveDOMCapturer,
            sessionPresenter: browserSessionPresenter
        )
        self.automationCoordinator = QuillCodeDesktopAutomationCoordinator()
        self.automationNotifier = automationNotifier
        self.navigationCoordinator = QuillCodeDesktopNavigationCoordinator()
        self.commandCoordinator = QuillCodeDesktopCommandCoordinator()
        self.signInCoordinator = QuillCodeDesktopSignInCoordinator(bootstrap: bootstrap)
        self.settingsCoordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)
        self.composerCoordinator = QuillCodeDesktopComposerCoordinator()
        self.copyCoordinator = QuillCodeDesktopCopyCoordinator()
        self.projectImportCoordinator = QuillCodeDesktopProjectImportCoordinator()
        self.modelStateCoordinator = QuillCodeDesktopModelStateCoordinator()
        self.paneCoordinator = QuillCodeDesktopPaneCoordinator()
        self.workspaceActionCoordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        self.terminalCoordinator = QuillCodeDesktopTerminalCoordinator()
        self.worktreeCoordinator = QuillCodeDesktopWorktreeCoordinator()
        do {
            self.model = try bootstrap.makeModel()
        } catch {
            self.model = QuillCodeWorkspaceModel()
        }
        self.workspaceRoot = workspaceRoot
        modelStateCoordinator.ensureDefaultProject(on: model, workspaceRoot: workspaceRoot)
        self.computerUseCoordinator.install(on: model)
        let initialState = modelStateCoordinator.initialState(from: model)
        self.surface = initialState.surface
        self.draft = initialState.draft
        self.terminalDraft = initialState.terminalDraft
        self.browserAddressDraft = initialState.browserAddressDraft
        browserCoordinator.installSessionUpdateHandler(
            model: model,
            refresh: { [weak self] in self?.refresh() }
        )
        automationCoordinator.runDueAutomations(
            model: model,
            notifier: automationNotifier,
            refresh: { [weak self] in self?.refresh() }
        )
        automationCoordinator.startTicker(
            model: model,
            tasks: tasks,
            notifier: automationNotifier,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func newChat() {
        // Stash the live draft to the outgoing thread before opening a new chat.
        model.setDraft(draft)
        navigationCoordinator.newChat(model: model)
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        refresh()
    }

    func selectThread(_ id: UUID) {
        // Persist the live in-progress draft to the outgoing thread before switching
        // so the model can stash it and restore the incoming thread's draft.
        model.setDraft(draft)
        navigationCoordinator.selectThread(id, model: model)
        // Force-sync the restored draft even mid-send (the busy gate would otherwise
        // keep the old thread's text visible under the newly selected thread).
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        refresh()
    }

    func runThreadAction(_ mutation: WorkspaceThreadRowMutation) {
        // Stash the live draft before a row action (duplicate/archive/delete) that
        // may change the selected thread, then force-sync the restored draft.
        model.setDraft(draft)
        navigationCoordinator.runThreadAction(mutation, model: model)
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        refresh()
    }

    func renameThread(_ id: UUID, title: String) {
        _ = navigationCoordinator.renameThread(id, title: title, model: model)
        refresh()
    }

    func saveSidebarSavedSearch(title: String, query: String) {
        _ = model.saveSidebarSavedSearch(title: title, query: query)
        refresh()
    }

    func selectProject(_ id: UUID?) {
        navigationCoordinator.selectProject(id, model: model)
        refresh()
    }

    func runProjectAction(_ mutation: WorkspaceProjectRowMutation) {
        navigationCoordinator.runProjectAction(mutation, model: model)
        refresh()
    }

    func renameProject(_ id: UUID, name: String) {
        _ = navigationCoordinator.renameProject(id, name: name, model: model)
        refresh()
    }

    func requestAddProject() {
        isProjectImporterPresented = true
    }

    func handleProjectImport(_ result: Result<[URL], Error>) {
        guard let selection = projectImportCoordinator.selectedProject(from: result) else {
            return
        }
        addProject(selection.url)
    }

    func addProject(_ url: URL) {
        navigationCoordinator.addProject(url, model: model)
        refresh()
    }

    func setMode(_ mode: AgentMode) {
        settingsCoordinator.setMode(mode, on: model)
        refresh()
    }

    func setModel(_ modelID: String) {
        settingsCoordinator.setModel(modelID, on: model)
        refresh()
    }

    func toggleModelFavorite(_ modelID: String) {
        settingsCoordinator.toggleModelFavorite(modelID, on: model)
        refresh()
    }

    func refreshModelCatalog() async {
        await settingsCoordinator.refreshModelCatalog(on: model)
        refresh()
    }

    func saveSettings(_ update: WorkspaceSettingsUpdate) {
        settingsCoordinator.saveSettings(
            update,
            to: model,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func startTrustedRouterSignIn() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await signInCoordinator.completeSignInAndApply(
                to: model,
                settingsCoordinator: settingsCoordinator,
                refresh: { [weak self] in self?.refresh() }
            )
        }
    }

    func send() {
        composerCoordinator.send(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func retryLastTurn() {
        composerCoordinator.retryLastTurn(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func runCommand(_ command: WorkspaceCommandSurface) {
        guard let action = QuillCodeDesktopCommandPlanner.action(for: command) else { return }
        commandCoordinator.run(action, performer: self)
    }

    func toggleTerminal() {
        paneCoordinator.toggleTerminal(on: model)
        refresh()
    }

    func toggleBrowser() {
        paneCoordinator.toggleBrowser(on: model)
        refresh()
    }

    func toggleExtensions() {
        paneCoordinator.toggleExtensions(on: model)
        refresh()
    }

    func toggleMemories() {
        paneCoordinator.toggleMemories(on: model)
        refresh()
    }

    func openBrowserPreview() {
        browserCoordinator.openPreview(
            model: model,
            addressDraft: browserAddressDraft,
            workspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func openBrowserSession() {
        browserCoordinator.openSession(
            model: model,
            addressDraft: browserAddressDraft,
            workspaceRoot: workspaceRoot,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func addBrowserComment(_ comment: String) {
        paneCoordinator.addBrowserComment(comment, to: model)
        refresh()
    }

    func runToolCardAction(_ action: ToolCardActionSurface) {
        workspaceActionCoordinator.runToolCardAction(
            action,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
        refresh()
    }

    func runTurnRevert(_ turnMessageID: UUID) {
        workspaceActionCoordinator.runTurnRevert(turnMessageID: turnMessageID, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func runTerminalCommand() {
        terminalCoordinator.runCommand(
            draft: &terminalDraft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func recallPreviousTerminalCommand() {
        terminalCoordinator.recallPreviousCommand(
            draft: &terminalDraft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func recallNextTerminalCommand() {
        terminalCoordinator.recallNextCommand(
            draft: &terminalDraft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func resizeTerminal(_ windowSize: TerminalWindowSize) {
        terminalCoordinator.resizeTerminal(windowSize, model: model)
    }

    func suspendTerminal() {
        terminalCoordinator.suspendTerminal(model: model)
        // Rebuild the published surface so the pane re-renders with the new isSuspended state
        // (Resume replaces Suspend). isSuspended is a visible surface field, unlike resize.
        refresh()
    }

    func resumeTerminal() {
        terminalCoordinator.resumeTerminal(model: model)
        refresh()
    }

    func runReviewAction(_ action: WorkspaceReviewActionSurface) {
        workspaceActionCoordinator.runReviewAction(action, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func runPullRequestReviewThreadAction(_ action: WorkspacePullRequestReviewThreadActionSurface) {
        workspaceActionCoordinator.runPullRequestReviewThreadAction(
            action,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        )
        refresh()
    }

    func runPullRequestReviewThreadReply(_ request: WorkspacePullRequestReviewThreadReplyRequest) {
        workspaceActionCoordinator.runPullRequestReviewThreadReply(
            request,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        )
        refresh()
    }

    func updatePullRequestReviewDraft(_ draft: WorkspacePullRequestReviewDraftSurface) {
        workspaceActionCoordinator.updatePullRequestReviewDraft(draft, model: model)
        refresh()
    }

    func cancelPullRequestReviewDraft() {
        workspaceActionCoordinator.cancelPullRequestReviewDraft(model: model)
        refresh()
    }

    func submitPullRequestReviewDraft() {
        workspaceActionCoordinator.submitPullRequestReviewDraft(model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func usePullRequestReviewThreadReplyDraft(_ draft: String) {
        workspaceActionCoordinator.useComposerDraft(draft, model: model)
        refresh()
    }

    func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int?,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) {
        workspaceActionCoordinator.addReviewComment(
            path: path,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            lineKind: lineKind,
            text: text,
            model: model
        )
        refresh()
    }

    func createWorktree(_ request: WorkspaceWorktreeCreateRequest) {
        worktreeCoordinator.createWorktree(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func worktreeChoiceLoad() async -> WorkspaceWorktreeChoiceLoad {
        await worktreeCoordinator.worktreeChoiceLoad(model: model, fallbackWorkspaceRoot: workspaceRoot)
    }

    func worktreePrunePreview() async -> WorkspaceWorktreePrunePreview {
        await worktreeCoordinator.worktreePrunePreview(model: model, fallbackWorkspaceRoot: workspaceRoot)
    }

    func openWorktree(_ request: WorkspaceWorktreeOpenRequest) {
        worktreeCoordinator.openWorktree(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest) {
        worktreeCoordinator.removeWorktree(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func pruneWorktrees(_ request: WorkspaceWorktreePruneRequest) {
        worktreeCoordinator.pruneWorktrees(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func copyTranscriptItem(id: String, text: String) {
        guard let feedback = copyCoordinator.copyTranscriptItem(id: id, text: text) else { return }
        copiedTranscriptItemID = feedback.copiedTranscriptItemID
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: feedback.clearAfterNanoseconds)
            await MainActor.run {
                if self?.copiedTranscriptItemID == id {
                    self?.copiedTranscriptItemID = nil
                }
            }
        }
    }

    func setMessageFeedback(messageID: UUID, value: MessageFeedbackValue) {
        guard workspaceActionCoordinator.setMessageFeedback(messageID: messageID, value: value, model: model) else {
            return
        }
        refresh()
    }

    func openCommandPalette() {
        isCommandPalettePresented = true
    }

    func openKeyboardShortcuts() {
        isKeyboardShortcutsPresented = true
    }

    func openSettings() {
        isSettingsPresented = true
    }

    func stopAll() {
        activeWorkCoordinator.stopAll(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    func disconnectAll() {
        activeWorkCoordinator.disconnectAll(
            draft: &draft,
            model: model,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
    }

    private func refresh() {
        computerUseCoordinator.refreshStatus(on: model)
        modelStateCoordinator.refreshState(
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft,
            isComposerTaskRunning: tasks.isRunning(.send)
        )
    }

    func openComputerUseSystemSettings(_ destination: MacSystemSettingsOpener.Destination) {
        computerUseCoordinator.openSystemSettings(destination, model: model)
        refresh()
    }
}

extension QuillCodeDesktopController: QuillCodeDesktopCommandPerforming {
    func refreshComputerUseStatus() {
        refresh()
    }

    func runWorkspaceCommand(_ commandID: String) {
        // Push the live draft so thread-changing commands (new chat / duplicate /
        // fork / compact) stash it instead of reading a stale model draft.
        model.setDraft(draft)
        guard workspaceActionCoordinator.runWorkspaceCommand(
            commandID,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        ) else {
            return
        }
        modelStateCoordinator.syncComposerDraft(from: model, draft: &draft)
        browserCoordinator.syncOpenSession(model: model)
        refresh()
    }
}
