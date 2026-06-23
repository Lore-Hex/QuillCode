import AppKit
import Foundation
import SwiftUI
import QuillCodeAgent
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
    private let automationNotifier: any QuillCodeAutomationNotifying
    private let workspaceRoot: URL
    private var sendTask: Task<Void, Never>?
    private var terminalTask: Task<Void, Never>?
    private var browserPreviewTask: Task<Void, Never>?
    private var automationTickTask: Task<Void, Never>?
    private var sendTaskID: UUID?
    private var terminalTaskID: UUID?
    private var browserPreviewTaskID: UUID?

    init(
        bootstrap: QuillCodeWorkspaceBootstrap = QuillCodeWorkspaceBootstrap(),
        browserPageFetcher: any BrowserPageFetching = URLSessionBrowserPageFetcher(),
        automationNotifier: any QuillCodeAutomationNotifying = MacAutomationNotifier(),
        workspaceRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) {
        self.bootstrap = bootstrap
        self.computerUseBackend = MacComputerUseBackend()
        self.browserPageFetcher = browserPageFetcher
        self.automationNotifier = automationNotifier
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

    deinit {
        automationTickTask?.cancel()
    }

    func newChat() {
        _ = model.newChat()
        refresh()
    }

    func selectThread(_ id: UUID) {
        model.selectThread(id)
        refresh()
    }

    func runThreadAction(_ action: SidebarItemActionSurface) {
        switch action.kind {
        case .rename:
            break
        case .duplicate:
            _ = model.duplicateThread(action.threadID)
        case .pin, .unpin:
            model.togglePinThread(action.threadID)
        case .archive:
            model.archiveThread(action.threadID)
        case .unarchive:
            model.unarchiveThread(action.threadID)
        case .delete:
            model.deleteThread(action.threadID)
        }
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

    func runProjectAction(_ action: ProjectItemActionSurface) {
        switch action.kind {
        case .newChat:
            _ = model.newChat(projectID: action.projectID)
        case .refreshContext:
            _ = model.refreshProjectContext(action.projectID)
        case .rename:
            break
        case .remove:
            _ = model.removeProject(action.projectID)
        }
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
        guard case let .success(urls) = result, let url = urls.first else {
            return
        }
        addProject(url)
    }

    func addProject(_ url: URL) {
        _ = model.addProject(path: url)
        refresh()
    }

    func setMode(_ mode: AgentMode) {
        model.setMode(mode)
        persistConfig()
        refresh()
    }

    func setModel(_ modelID: String) {
        model.setModel(modelID)
        persistConfig()
        refresh()
    }

    func toggleModelFavorite(_ modelID: String) {
        model.toggleModelFavorite(modelID)
        persistConfig()
        refresh()
    }

    func refreshModelCatalog() async {
        let models = await bootstrap.fetchModelCatalog(config: model.root.config)
        model.setModelCatalog(models)
        refresh()
    }

    func saveSettings(_ update: WorkspaceSettingsUpdate) {
        var config = model.root.config
        config.apiBaseURL = update.apiBaseURL
        config.authMode = update.authMode
        config.developerOverrideEnabled = update.developerOverrideEnabled || update.authMode == .developerOverride
        if update.shouldClearAPIKey {
            try? bootstrap.clearTrustedRouterAPIKey()
            config.trustedRouterAccount = nil
        }
        if let replacementAPIKey = update.replacementAPIKey {
            try? bootstrap.saveTrustedRouterAPIKey(replacementAPIKey)
            config.trustedRouterAccount = nil
        }
        if config.authMode == .developerOverride {
            config.trustedRouterAccount = nil
        }
        try? bootstrap.saveConfig(config)
        model.applySettings(
            config: config,
            trustedRouterAPIKeyConfigured: bootstrap.hasTrustedRouterAPIKey()
        )
        model.applyRuntime(bootstrap.makeRuntime(config: config))
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
        guard !prompt.isEmpty, sendTask == nil else { return }
        model.setDraft(prompt)
        draft = ""
        refresh()
        submitPreparedComposer()
    }

    func retryLastTurn() {
        guard sendTask == nil, model.prepareRetryLastUserTurn() else { return }
        draft = ""
        refresh()
        submitPreparedComposer()
    }

    func runCommand(_ command: WorkspaceCommandSurface) {
        switch command.id {
        case "new-chat":
            newChat()
        case "add-project":
            requestAddProject()
        case "toggle-terminal":
            toggleTerminal()
        case "toggle-browser":
            toggleBrowser()
        case "toggle-extensions":
            toggleExtensions()
        case "toggle-memories":
            toggleMemories()
        case "command-palette":
            openCommandPalette()
        case "settings", "computer-use-setup":
            openSettings()
        case "computer-use-open-screen-recording":
            openComputerUseSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case "computer-use-open-accessibility":
            openComputerUseSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case "computer-use-refresh":
            refresh()
        case "stop-all":
            stopAll()
        case "retry-last-turn":
            retryLastTurn()
        default:
            if model.runWorkspaceCommand(command.id, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot) {
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
        browserPreviewTask?.cancel()
        model.setBrowserAddressDraft(browserAddressDraft)
        _ = model.openBrowserPreview(workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
        let taskID = UUID()
        browserPreviewTaskID = taskID
        browserPreviewTask = Task { @MainActor in
            _ = await model.refreshBrowserSnapshot(pageFetcher: browserPageFetcher)
            if browserPreviewTaskID == taskID {
                browserPreviewTask = nil
                browserPreviewTaskID = nil
            }
            refresh()
        }
    }

    func addBrowserComment(_ comment: String) {
        _ = model.addBrowserComment(comment)
        refresh()
    }

    func runTerminalCommand() {
        let command = terminalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, terminalTask == nil else { return }
        terminalDraft = ""
        refresh()
        let taskID = UUID()
        terminalTaskID = taskID
        terminalTask = Task { @MainActor in
            await model.runTerminalCommand(command, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
            if terminalTaskID == taskID {
                terminalTask = nil
                terminalTaskID = nil
            }
            refresh()
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

    func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest) {
        model.removeWorktree(request, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
        refresh()
    }

    func copyTranscriptItem(id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedTranscriptItemID = id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
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
        sendTask?.cancel()
        terminalTask?.cancel()
        browserPreviewTask?.cancel()
        sendTask = nil
        terminalTask = nil
        browserPreviewTask = nil
        sendTaskID = nil
        terminalTaskID = nil
        browserPreviewTaskID = nil
        model.cancelActiveWork()
        draft = ""
        refresh()
    }

    private func completeTrustedRouterSignIn() async {
        model.setAgentStatus("Opening TrustedRouter")
        refresh()
        do {
            let client = try TrustedRouterOAuthClient(baseURL: model.root.config.apiBaseURL)
            let server = try TrustedRouterLoopbackCallbackServer()
            try await server.start()
            defer { server.cancel() }

            let authorization = try client.createAuthorization(
                callbackURL: TrustedRouterLoopbackCallbackServer.callbackURL,
                keyLabel: "QuillCode"
            )
            NSWorkspace.shared.open(authorization.url)
            model.setAgentStatus("Waiting for TrustedRouter")
            refresh()

            let callbackURL = try await server.waitForCallback()
            model.setAgentStatus("Finishing sign-in")
            refresh()
            let code = try client.parseCallback(callbackURL, expectedState: authorization.state)
            let token = try await client.exchangeCode(
                code: code,
                codeVerifier: authorization.codeVerifier
            )
            let account = await trustedRouterAccountProfile(from: token, client: client)

            try bootstrap.saveTrustedRouterAPIKey(token.key)
            var config = model.root.config
            config.authMode = .oauth
            config.developerOverrideEnabled = false
            config.trustedRouterAccount = account
            try bootstrap.saveConfig(config)
            model.applySettings(
                config: config,
                trustedRouterAPIKeyConfigured: true
            )
            model.applyRuntime(bootstrap.makeRuntime(config: config))
            refresh()
            await refreshModelCatalog()
        } catch {
            model.setAgentStatus("Sign-in failed", lastError: String(describing: error))
            refresh()
        }
    }

    private func trustedRouterAccountProfile(
        from token: TrustedRouterOAuthToken,
        client: TrustedRouterOAuthClient
    ) async -> TrustedRouterAccountProfile? {
        var profile = TrustedRouterAccountProfile(
            userID: token.userID,
            subject: token.identity?.sub,
            email: token.identity?.email,
            walletAddress: token.identity?.walletAddress
        )
        if let userInfo = try? await client.fetchUserInfo(apiKey: token.key) {
            profile = TrustedRouterAccountProfile(
                userID: profile.userID,
                subject: profile.subject ?? userInfo.data.sub,
                email: profile.email ?? userInfo.data.email,
                walletAddress: profile.walletAddress ?? userInfo.data.walletAddress
            )
        }
        return profile.isEmpty ? nil : profile
    }

    private func submitPreparedComposer() {
        let taskID = UUID()
        sendTaskID = taskID
        sendTask = Task { @MainActor in
            await model.submitComposer(workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
            if sendTaskID == taskID {
                sendTask = nil
                sendTaskID = nil
            }
            refresh()
        }
    }

    private func startAutomationTicker() {
        automationTickTask?.cancel()
        automationTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.runDueAutomations()
                }
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

    private func persistConfig() {
        try? bootstrap.saveConfig(model.root.config)
    }

    private func openComputerUseSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        refresh()
    }
}
