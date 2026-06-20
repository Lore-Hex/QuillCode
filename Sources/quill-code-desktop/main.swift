import SwiftUI
import UniformTypeIdentifiers
import AppKit
import QuillCodeApp
import QuillCodeCore

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
                .keyboardShortcut("n", modifiers: .command)
                Button("Open Project...") {
                    NotificationCenter.default.post(name: .quillCodeOpenProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Toggle Terminal") {
                    NotificationCenter.default.post(name: .quillCodeToggleTerminal, object: nil)
                }
                .keyboardShortcut("`", modifiers: .control)
                Button("Toggle Browser") {
                    NotificationCenter.default.post(name: .quillCodeToggleBrowser, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .quillCodeCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Settings...") {
                    NotificationCenter.default.post(name: .quillCodeOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        MenuBarExtra {
            QuillCodeMenuBarView(
                surface: controller.surface,
                onNewChat: controller.newChat,
                onOpenProject: controller.requestAddProject,
                onCommandPalette: controller.openCommandPalette,
                onSettings: controller.openSettings,
                onToggleTerminal: controller.toggleTerminal,
                onToggleBrowser: controller.toggleBrowser,
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
            onSend: controller.send,
            onRunTerminalCommand: controller.runTerminalCommand,
            onOpenBrowserPreview: controller.openBrowserPreview,
            onAddBrowserComment: controller.addBrowserComment,
            onAddProjectRequested: controller.requestAddProject,
            onSelectThread: controller.selectThread,
            onThreadAction: controller.runThreadAction,
            onSelectProject: controller.selectProject,
            onSetMode: controller.setMode,
            onSetModel: controller.setModel,
            onSaveSettings: controller.saveSettings,
            onReviewAction: controller.runReviewAction,
            onAddReviewComment: controller.addReviewComment,
            onCreateWorktree: controller.createWorktree,
            onRemoveWorktree: controller.removeWorktree,
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
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeOpenProject)) { _ in
            controller.requestAddProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeCommandPalette)) { _ in
            controller.openCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeOpenSettings)) { _ in
            controller.openSettings()
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
    @Published var isProjectImporterPresented = false

    private let model: QuillCodeWorkspaceModel
    private let bootstrap: QuillCodeWorkspaceBootstrap
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
        do {
            self.model = try bootstrap.makeModel()
        } catch {
            self.model = QuillCodeWorkspaceModel()
        }
        self.workspaceRoot = workspaceRoot
        if self.model.root.projects.isEmpty {
            _ = self.model.addProject(path: workspaceRoot)
        }
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
        case .pin, .unpin:
            model.togglePinThread(action.threadID)
        case .archive:
            model.archiveThread(action.threadID)
        }
        refresh()
    }

    func selectProject(_ id: UUID?) {
        model.selectProject(id)
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

    func refreshModelCatalog() async {
        let models = await bootstrap.fetchModelCatalog(config: model.root.config)
        model.setModelCatalog(models)
        refresh()
    }

    func saveSettings(_ update: WorkspaceSettingsUpdate) {
        var config = model.root.config
        config.apiBaseURL = update.apiBaseURL
        config.developerOverrideEnabled = update.developerOverrideEnabled
        if update.shouldClearAPIKey {
            try? bootstrap.clearTrustedRouterAPIKey()
        }
        if let replacementAPIKey = update.replacementAPIKey {
            try? bootstrap.saveTrustedRouterAPIKey(replacementAPIKey)
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

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, sendTask == nil else { return }
        model.setDraft(prompt)
        draft = ""
        refresh()
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
        case "command-palette":
            openCommandPalette()
        case "stop-all":
            stopAll()
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

    func addReviewComment(path: String, text: String) {
        _ = model.addReviewComment(path: path, text: text)
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

    func openCommandPalette() {
        isCommandPalettePresented = true
    }

    func openSettings() {
        isSettingsPresented = true
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
    var onSettings: () -> Void
    var onToggleTerminal: () -> Void
    var onToggleBrowser: () -> Void
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
        Text("Thread: \(surface.topBar.primaryTitle)")
        Text("Model: \(surface.topBar.modelLabel)")
        Text("Mode: \(surface.topBar.modeLabel)")
        Text("Computer Use: \(surface.topBar.computerUseLabel)")
        Divider()
        Button("New Chat", action: onNewChat)
        Button("Open Project...", action: onOpenProject)
        Button("Command Palette", action: onCommandPalette)
        Button(surface.terminal.isVisible ? "Hide Terminal" : "Show Terminal", action: onToggleTerminal)
        Button(surface.browser.isVisible ? "Hide Browser" : "Show Browser", action: onToggleBrowser)
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
    static let quillCodeToggleTerminal = Notification.Name("QuillCodeToggleTerminal")
    static let quillCodeToggleBrowser = Notification.Name("QuillCodeToggleBrowser")
    static let quillCodeOpenSettings = Notification.Name("QuillCodeOpenSettings")
}
