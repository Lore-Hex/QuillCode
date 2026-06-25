import Foundation
import SwiftUI
import QuillCodeApp
import QuillCodeCore
import QuillComputerUseKit

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
    private let computerUseBackend: MacComputerUseBackend
    private let browserPageFetcher: any BrowserPageFetching
    private let browserLiveDOMCapturer: (any BrowserLiveDOMCapturing)?
    private let browserSessionPresenter: any DesktopBrowserSessionPresenting
    private let automationNotifier: any QuillCodeAutomationNotifying
    private let workspaceRoot: URL
    private let signInCoordinator: QuillCodeDesktopSignInCoordinator
    private let settingsCoordinator: QuillCodeDesktopSettingsCoordinator
    private let systemSettingsOpener: MacSystemSettingsOpener
    private let copyCoordinator: QuillCodeDesktopCopyCoordinator
    private let projectImportCoordinator: QuillCodeDesktopProjectImportCoordinator
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
        self.computerUseBackend = MacComputerUseBackend()
        self.browserPageFetcher = browserPageFetcher
        self.browserLiveDOMCapturer = browserLiveDOMCapturer
        self.browserSessionPresenter = browserSessionPresenter
        self.automationNotifier = automationNotifier
        self.signInCoordinator = QuillCodeDesktopSignInCoordinator(bootstrap: bootstrap)
        self.settingsCoordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)
        self.systemSettingsOpener = MacSystemSettingsOpener()
        self.copyCoordinator = QuillCodeDesktopCopyCoordinator()
        self.projectImportCoordinator = QuillCodeDesktopProjectImportCoordinator()
        do {
            self.model = try bootstrap.makeModel()
        } catch {
            self.model = QuillCodeWorkspaceModel()
        }
        self.workspaceRoot = workspaceRoot
        if self.model.root.projects.isEmpty {
            _ = self.model.addProject(path: workspaceRoot)
        }
        self.model.setComputerUseBackend(computerUseBackend)
        self.surface = model.surface()
        self.draft = model.composer.draft
        self.terminalDraft = model.terminal.draft
        self.browserAddressDraft = model.browser.addressDraft
        runDueAutomations()
        startAutomationTicker()
    }

    func newChat() {
        _ = model.newChat()
        refresh()
    }

    func selectThread(_ id: UUID) {
        model.selectThread(id)
        refresh()
    }

    func runThreadAction(_ mutation: WorkspaceThreadRowMutation) {
        WorkspaceSidebarRowMutationExecutor.execute(mutation, model: model)
        refresh()
    }

    func renameThread(_ id: UUID, title: String) {
        _ = model.renameThread(id, to: title)
        refresh()
    }

    func selectProject(_ id: UUID?) {
        model.selectProject(id)
        refresh()
    }

    func runProjectAction(_ mutation: WorkspaceProjectRowMutation) {
        WorkspaceSidebarRowMutationExecutor.execute(mutation, model: model)
        refresh()
    }

    func renameProject(_ id: UUID, name: String) {
        _ = model.renameProject(id, to: name)
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
        _ = model.addProject(path: url)
        refresh()
    }

    func setMode(_ mode: AgentMode) {
        model.setMode(mode)
        settingsCoordinator.persist(model.root.config)
        refresh()
    }

    func setModel(_ modelID: String) {
        model.setModel(modelID)
        settingsCoordinator.persist(model.root.config)
        refresh()
    }

    func toggleModelFavorite(_ modelID: String) {
        model.toggleModelFavorite(modelID)
        settingsCoordinator.persist(model.root.config)
        refresh()
    }

    func refreshModelCatalog() async {
        let models = await bootstrap.fetchModelCatalog(config: model.root.config)
        model.setModelCatalog(models)
        refresh()
    }

    func saveSettings(_ update: WorkspaceSettingsUpdate) {
        let result = settingsCoordinator.apply(
            update: update,
            currentConfig: model.root.config
        )
        model.applySettings(
            config: result.config,
            trustedRouterAPIKeyConfigured: result.trustedRouterAPIKeyConfigured
        )
        model.applyRuntime(result.runtime)
        refresh()
        Task {
            await refreshModelCatalog()
        }
    }

    func startTrustedRouterSignIn() {
        Task { @MainActor in
            await completeTrustedRouterSignIn()
        }
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !tasks.isRunning(.send) else { return }
        model.setDraft(prompt)
        draft = ""
        refresh()
        submitPreparedComposer()
    }

    func retryLastTurn() {
        guard !tasks.isRunning(.send), model.prepareRetryLastUserTurn() else { return }
        draft = ""
        refresh()
        submitPreparedComposer()
    }

    func runCommand(_ command: WorkspaceCommandSurface) {
        guard let action = QuillCodeDesktopCommandPlanner.action(for: command) else { return }
        runCommandAction(action)
    }

    private func runCommandAction(_ action: QuillCodeDesktopCommandAction) {
        switch action {
        case .newChat:
            newChat()
        case .addProject:
            requestAddProject()
        case .toggleTerminal:
            toggleTerminal()
        case .toggleBrowser:
            toggleBrowser()
        case .openBrowserSession:
            openBrowserSession()
        case .toggleExtensions:
            toggleExtensions()
        case .toggleMemories:
            toggleMemories()
        case .commandPalette:
            openCommandPalette()
        case .settings:
            openSettings()
        case .openComputerUseSystemSettings(let destination):
            openComputerUseSystemSettings(destination)
        case .refreshComputerUseStatus:
            refresh()
        case .stopAll:
            stopAll()
        case .disconnectAll:
            disconnectAll()
        case .retryLastTurn:
            retryLastTurn()
        case .workspaceCommand(let commandID):
            if model.runWorkspaceCommand(commandID, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot) {
                draft = model.composer.draft
                refresh()
            }
        }
    }

    func toggleTerminal() {
        model.toggleTerminal()
        refresh()
    }

    func toggleBrowser() {
        model.toggleBrowser()
        refresh()
    }

    func toggleExtensions() {
        model.toggleExtensions()
        refresh()
    }

    func toggleMemories() {
        model.toggleMemories()
        refresh()
    }

    func openBrowserPreview() {
        model.setBrowserAddressDraft(browserAddressDraft)
        _ = model.openBrowserPreview(workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
        tasks.replace(.browserPreview) { [weak self] in
            guard let self else { return }
            _ = await self.model.refreshBrowserSnapshot(pageFetcher: self.browserPageFetcher)
            if let browserLiveDOMCapturer = self.browserLiveDOMCapturer {
                _ = await self.model.refreshRenderedBrowserSnapshot(capturer: browserLiveDOMCapturer)
            }
        } onFinish: { [weak self] in
            self?.refresh()
        }
    }

    func openBrowserSession() {
        let root = model.activeWorkspaceRoot ?? workspaceRoot
        let rawAddress = browserAddressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAddress = model.browser.currentURL ?? model.browser.addressDraft
        let targetAddress = rawAddress.isEmpty ? fallbackAddress : rawAddress
        guard let url = WorkspaceBrowserLocationResolver(workspaceRoot: root).resolve(targetAddress) else {
            model.setBrowserAddressDraft(targetAddress)
            _ = model.openBrowserPreview(workspaceRoot: root)
            refresh()
            return
        }

        browserSessionPresenter.openSession(url: url)
        if model.browser.currentURL != url.absoluteString {
            model.setBrowserAddressDraft(url.absoluteString)
            _ = model.openBrowserPreview(workspaceRoot: root)
        }
        refresh()
    }

    func addBrowserComment(_ comment: String) {
        _ = model.addBrowserComment(comment)
        refresh()
    }

    func runToolCardAction(_ action: ToolCardActionSurface) {
        _ = model.runToolCardAction(action, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
    }

    func runTerminalCommand() {
        let command = terminalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !tasks.isRunning(.terminal) else { return }
        terminalDraft = ""
        refresh()
        tasks.startIfIdle(.terminal) { [weak self] in
            guard let self else { return }
            await self.model.runTerminalCommand(
                command,
                workspaceRoot: self.model.activeWorkspaceRoot ?? self.workspaceRoot
            )
        } onFinish: { [weak self] in
            self?.refresh()
        }
    }

    func runReviewAction(_ action: WorkspaceReviewActionSurface) {
        model.runReviewAction(action, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
    }

    func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int?,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) {
        _ = model.addReviewComment(
            path: path,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            lineKind: lineKind,
            text: text
        )
        refresh()
    }

    func createWorktree(_ request: WorkspaceWorktreeCreateRequest) {
        model.createWorktree(request, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
    }

    func worktreeChoices() -> [WorkspaceWorktreeChoice] {
        model.worktreeChoices(workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
    }

    func openWorktree(_ request: WorkspaceWorktreeOpenRequest) {
        model.openWorktree(request, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
    }

    func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest) {
        model.removeWorktree(request, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
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
        guard model.setMessageFeedback(messageID: messageID, value: value) else { return }
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
        tasks.cancel([.send, .terminal, .browserPreview])
        model.cancelActiveWork()
        draft = ""
        refresh()
    }

    func disconnectAll() {
        tasks.cancel([.send, .terminal, .browserPreview])
        guard model.disconnectAll() else {
            refresh()
            return
        }
        draft = ""
        refresh()
    }

    private func completeTrustedRouterSignIn() async {
        do {
            let result = try await signInCoordinator.completeSignIn(
                currentConfig: model.root.config
            ) { [weak self] label, error in
                self?.model.setAgentStatus(label, lastError: error)
                self?.refresh()
            }
            let settings = settingsCoordinator.result(for: result.config)
            model.applySettings(
                config: settings.config,
                trustedRouterAPIKeyConfigured: settings.trustedRouterAPIKeyConfigured
            )
            model.applyRuntime(settings.runtime)
            refresh()
            await refreshModelCatalog()
        } catch {
            model.setAgentStatus(
                QuillCodeRuntimeStatusLabel.signInFailed,
                lastError: String(describing: error)
            )
            refresh()
        }
    }

    private func submitPreparedComposer() {
        tasks.startIfIdle(.send) { [weak self] in
            guard let self else { return }
            await self.model.submitComposer(workspaceRoot: self.model.activeWorkspaceRoot ?? self.workspaceRoot)
        } onFinish: { [weak self] in
            self?.refresh()
        }
    }

    private func startAutomationTicker() {
        tasks.replace(.automationTicker) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else {
                    return
                }
                self.runDueAutomations()
            }
        }
    }

    private func runDueAutomations() {
        let reports = model.runDueAutomationReports()
        guard !reports.isEmpty else { return }
        reports.forEach(automationNotifier.deliver)
        refresh()
    }

    private func refresh() {
        model.setComputerUseStatus(computerUseBackend.status)
        surface = model.surface()
        if draft != model.composer.draft, !model.composer.isSending {
            draft = model.composer.draft
        }
        if terminalDraft != model.terminal.draft, !model.terminal.isRunning {
            terminalDraft = model.terminal.draft
        }
        if browserAddressDraft != model.browser.addressDraft {
            browserAddressDraft = model.browser.addressDraft
        }
    }

    private func openComputerUseSystemSettings(_ destination: MacSystemSettingsOpener.Destination) {
        systemSettingsOpener.open(destination)
        refresh()
    }
}
