import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Network
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillComputerUseKit

@main
struct QuillCodeDesktopApp: App {
    @StateObject private var controller = QuillCodeDesktopController()

    var body: some Scene {
        WindowGroup("QuillCode") {
            QuillCodeDesktopRootView(controller: controller)
        }
        .commands {
            CommandMenu("QuillCode") {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .quillCodeNewChat, object: nil)
                }
                .quillCodeShortcut("new-chat")
                Button("Open Project...") {
                    NotificationCenter.default.post(name: .quillCodeOpenProject, object: nil)
                }
                .quillCodeShortcut("add-project")
                Button("Toggle Terminal") {
                    NotificationCenter.default.post(name: .quillCodeToggleTerminal, object: nil)
                }
                .quillCodeShortcut("toggle-terminal")
                Button("Toggle Browser") {
                    NotificationCenter.default.post(name: .quillCodeToggleBrowser, object: nil)
                }
                .quillCodeShortcut("toggle-browser")
                Button("Toggle Extensions") {
                    NotificationCenter.default.post(name: .quillCodeToggleExtensions, object: nil)
                }
                Button("Toggle Memories") {
                    NotificationCenter.default.post(name: .quillCodeToggleMemories, object: nil)
                }
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .quillCodeCommandPalette, object: nil)
                }
                .quillCodeShortcut("command-palette")
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .quillCodeKeyboardShortcuts, object: nil)
                }
                .quillCodeShortcut("keyboard-shortcuts")
                Button("Settings...") {
                    NotificationCenter.default.post(name: .quillCodeOpenSettings, object: nil)
                }
                .quillCodeShortcut("settings")
                Button("Stop All") {
                    NotificationCenter.default.post(name: .quillCodeStopAll, object: nil)
                }
                .quillCodeShortcut("stop-all")
                Button("Retry Last Turn") {
                    NotificationCenter.default.post(name: .quillCodeRetryLastTurn, object: nil)
                }
            }
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
                onToggleExtensions: controller.toggleExtensions,
                onToggleMemories: controller.toggleMemories,
                onStopAll: controller.stopAll,
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

private struct QuillCodeDesktopRootView: View {
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
            onOpenBrowserPreview: controller.openBrowserPreview,
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
            onAddReviewComment: controller.addReviewComment,
            onCreateWorktree: controller.createWorktree,
            onRemoveWorktree: controller.removeWorktree,
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

@MainActor
private final class QuillCodeDesktopController: ObservableObject {
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
    private let workspaceRoot: URL
    private var sendTask: Task<Void, Never>?
    private var terminalTask: Task<Void, Never>?
    private var sendTaskID: UUID?
    private var terminalTaskID: UUID?

    init(
        bootstrap: QuillCodeWorkspaceBootstrap = QuillCodeWorkspaceBootstrap(),
        workspaceRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) {
        self.bootstrap = bootstrap
        self.computerUseBackend = MacComputerUseBackend()
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
            break
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

    private func persistConfig() {
        try? bootstrap.saveConfig(model.root.config)
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

    private func openComputerUseSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        refresh()
    }

    func stopAll() {
        sendTask?.cancel()
        terminalTask?.cancel()
        sendTask = nil
        terminalTask = nil
        sendTaskID = nil
        terminalTaskID = nil
        model.cancelActiveWork()
        draft = ""
        refresh()
    }
}

private struct QuillCodeMenuBarView: View {
    var surface: WorkspaceSurface
    var onNewChat: () -> Void
    var onOpenProject: () -> Void
    var onCommandPalette: () -> Void
    var onKeyboardShortcuts: () -> Void
    var onSettings: () -> Void
    var onToggleTerminal: () -> Void
    var onToggleBrowser: () -> Void
    var onToggleExtensions: () -> Void
    var onToggleMemories: () -> Void
    var onStopAll: () -> Void
    var onComputerUseSetup: () -> Void
    var onQuit: () -> Void

    var body: some View {
        Text(surface.topBar.appName)
            .font(.headline)
        Text(surface.topBar.subtitle)
            .font(.caption)
        Divider()
        Label(surface.topBar.agentStatus, systemImage: statusSystemImage)
        if let issue = surface.runtimeIssue {
            Label(issue.title, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
            Text(issue.message)
                .font(.caption)
        }
        Text("Thread: \(surface.topBar.primaryTitle)")
        Text("Model: \(surface.topBar.modelLabel)")
        Text("Mode: \(surface.topBar.modeLabel)")
        Text("Computer Use: \(surface.topBar.computerUseLabel)")
        Divider()
        Button("New Chat", action: onNewChat)
        Button("Open Project...", action: onOpenProject)
        Button("Command Palette", action: onCommandPalette)
        Button("Keyboard Shortcuts", action: onKeyboardShortcuts)
        Button(surface.terminal.isVisible ? "Hide Terminal" : "Show Terminal", action: onToggleTerminal)
        Button(surface.browser.isVisible ? "Hide Browser" : "Show Browser", action: onToggleBrowser)
        Button(surface.memories.isVisible ? "Hide Memories" : "Show Memories", action: onToggleMemories)
        Button(surface.extensions.isVisible ? "Hide Extensions" : "Show Extensions", action: onToggleExtensions)
        if surface.topBar.showsComputerUseSetup {
            Button("Computer Use Setup", action: onComputerUseSetup)
        }
        Button("Settings...", action: onSettings)
        Divider()
        Button("Stop All", action: onStopAll)
            .disabled(!surface.composer.isSending && !surface.terminal.isRunning)
        Button("Disconnect All") {}
            .disabled(true)
        Divider()
        Button("Quit QuillCode", action: onQuit)
    }

    private var statusSystemImage: String {
        switch surface.topBar.agentStatus.lowercased() {
        case let status where status.contains("fail"):
            return "xmark.circle"
        case let status where status.contains("running") || status.contains("terminal"):
            return "arrow.triangle.2.circlepath"
        default:
            return "checkmark.circle"
        }
    }
}

private extension Notification.Name {
    static let quillCodeNewChat = Notification.Name("QuillCodeNewChat")
    static let quillCodeOpenProject = Notification.Name("QuillCodeOpenProject")
    static let quillCodeCommandPalette = Notification.Name("QuillCodeCommandPalette")
    static let quillCodeKeyboardShortcuts = Notification.Name("QuillCodeKeyboardShortcuts")
    static let quillCodeToggleTerminal = Notification.Name("QuillCodeToggleTerminal")
    static let quillCodeToggleBrowser = Notification.Name("QuillCodeToggleBrowser")
    static let quillCodeToggleExtensions = Notification.Name("QuillCodeToggleExtensions")
    static let quillCodeToggleMemories = Notification.Name("QuillCodeToggleMemories")
    static let quillCodeOpenSettings = Notification.Name("QuillCodeOpenSettings")
    static let quillCodeStopAll = Notification.Name("QuillCodeStopAll")
    static let quillCodeRetryLastTurn = Notification.Name("QuillCodeRetryLastTurn")
}

private extension View {
    func quillCodeShortcut(_ commandID: String) -> some View {
        guard let shortcut = WorkspaceShortcutRegistry.shortcut(for: commandID) else {
            return AnyView(self)
        }
        return AnyView(keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers))
    }
}

private extension WorkspaceShortcut {
    var keyEquivalent: KeyEquivalent {
        switch key {
        case "escape":
            return .escape
        case "`":
            return "`"
        case ",":
            return ","
        default:
            return KeyEquivalent(Character(key))
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) {
            result.insert(.command)
        }
        if modifiers.contains(.control) {
            result.insert(.control)
        }
        if modifiers.contains(.option) {
            result.insert(.option)
        }
        if modifiers.contains(.shift) {
            result.insert(.shift)
        }
        return result
    }
}

private enum TrustedRouterLoopbackError: Error, CustomStringConvertible {
    case invalidPort
    case listenerFailed(String)
    case cancelled
    case invalidCallbackRequest

    var description: String {
        switch self {
        case .invalidPort:
            return "Could not reserve localhost OAuth callback port 3000."
        case .listenerFailed(let message):
            return "TrustedRouter sign-in callback server failed: \(message)"
        case .cancelled:
            return "TrustedRouter sign-in was cancelled."
        case .invalidCallbackRequest:
            return "TrustedRouter sign-in callback request was invalid."
        }
    }
}

private final class TrustedRouterLoopbackCallbackServer: @unchecked Sendable {
    static let callbackURL = TrustedRouterDefaults.loopbackCallbackURL
    private static let callbackBaseURL = URL(string: TrustedRouterDefaults.loopbackCallbackURL)!
    private static let callbackPath = callbackBaseURL.path.isEmpty ? "/" : callbackBaseURL.path

    private let queue = DispatchQueue(label: "co.lorehex.quillcode.oauth-loopback")
    private let listener: NWListener
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallbackResult: Result<URL, Error>?
    private var isStarted = false
    private var isFinished = false

    init() throws {
        guard let port = NWEndpoint.Port(rawValue: 3000) else {
            throw TrustedRouterLoopbackError.invalidPort
        }
        self.listener = try NWListener(using: .tcp, on: port)
        self.listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        self.listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.isStarted {
                    continuation.resume()
                    return
                }
                self.startContinuation = continuation
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.pendingCallbackResult {
                    self.pendingCallbackResult = nil
                    continuation.resume(with: result)
                    return
                }
                self.callbackContinuation = continuation
            }
        }
    }

    func cancel() {
        queue.async {
            self.finish(.failure(TrustedRouterLoopbackError.cancelled), cancelListener: true)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isStarted = true
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error):
            finish(.failure(TrustedRouterLoopbackError.listenerFailed(String(describing: error))), cancelListener: true)
        case .cancelled:
            if !isFinished {
                finish(.failure(TrustedRouterLoopbackError.cancelled), cancelListener: false)
            }
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                self.sendHTML(
                    status: "400 Bad Request",
                    body: "QuillCode could not read the TrustedRouter callback.",
                    on: connection
                )
                self.finish(.failure(TrustedRouterLoopbackError.listenerFailed(String(describing: error))), cancelListener: true)
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let target = self.requestTarget(from: request)
            else {
                self.sendHTML(
                    status: "400 Bad Request",
                    body: "QuillCode received an invalid TrustedRouter callback.",
                    on: connection
                )
                self.finish(.failure(TrustedRouterLoopbackError.invalidCallbackRequest), cancelListener: true)
                return
            }
            guard Self.isCallbackTarget(target),
                  let callbackURL = URL(string: "\(Self.callbackURL)\(target.dropFirst(Self.callbackPath.count))")
            else {
                self.sendHTML(
                    status: "404 Not Found",
                    body: "QuillCode is waiting for the TrustedRouter sign-in callback.",
                    on: connection
                )
                return
            }

            self.sendHTML(
                status: "200 OK",
                body: "QuillCode sign-in complete. You can return to QuillCode.",
                on: connection
            ) {
                self.finish(.success(callbackURL), cancelListener: true)
            }
        }
    }

    private static func isCallbackTarget(_ target: String) -> Bool {
        target == callbackPath || target.hasPrefix("\(callbackPath)?")
    }

    private func requestTarget(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
        return String(parts[1])
    }

    private func sendHTML(
        status: String,
        body: String,
        on connection: NWConnection,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let escapedBody = body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html>
        <html lang="en">
          <head><meta charset="utf-8"><title>QuillCode</title></head>
          <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 40px;">
            <h1>\(escapedBody)</h1>
          </body>
        </html>
        """
        let bodyData = Data(html.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var payload = Data(headers.utf8)
        payload.append(bodyData)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
            completion?()
        })
    }

    private func finish(_ result: Result<URL, Error>, cancelListener: Bool) {
        guard !isFinished else {
            return
        }
        isFinished = true
        if let startContinuation {
            switch result {
            case .success:
                startContinuation.resume()
            case .failure(let error):
                startContinuation.resume(throwing: error)
            }
        }
        startContinuation = nil
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            pendingCallbackResult = result
        }
        if cancelListener {
            listener.cancel()
        }
    }
}
