import SwiftUI
import UniformTypeIdentifiers
import QuillCodeApp
import QuillCodeCore

@main
struct QuillCodeDesktopApp: App {
    var body: some Scene {
        WindowGroup("QuillCode") {
            QuillCodeDesktopRootView()
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
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .quillCodeCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

private struct QuillCodeDesktopRootView: View {
    @StateObject private var controller = QuillCodeDesktopController()

    var body: some View {
        QuillCodeWorkspaceView(
            surface: controller.surface,
            draft: $controller.draft,
            terminalDraft: $controller.terminalDraft,
            isCommandPalettePresented: $controller.isCommandPalettePresented,
            onSend: controller.send,
            onRunTerminalCommand: controller.runTerminalCommand,
            onAddProjectRequested: controller.requestAddProject,
            onSelectThread: controller.selectThread,
            onThreadAction: controller.runThreadAction,
            onSelectProject: controller.selectProject,
            onSetMode: controller.setMode,
            onSetModel: controller.setModel,
            onSaveSettings: controller.saveSettings,
            onReviewAction: controller.runReviewAction,
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
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeOpenProject)) { _ in
            controller.requestAddProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeCommandPalette)) { _ in
            controller.openCommandPalette()
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
    @Published var isCommandPalettePresented = false
    @Published var isProjectImporterPresented = false

    private let model: QuillCodeWorkspaceModel
    private let bootstrap: QuillCodeWorkspaceBootstrap
    private let workspaceRoot: URL

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
        guard !prompt.isEmpty else { return }
        model.setDraft(prompt)
        draft = ""
        refresh()
        Task {
            await model.submitComposer(workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
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
        case "command-palette":
            openCommandPalette()
        case "stop-all":
            break
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

    func runTerminalCommand() {
        let command = terminalDraft
        terminalDraft = ""
        Task {
            await model.runTerminalCommand(command, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
            refresh()
        }
    }

    func runReviewAction(_ action: WorkspaceReviewActionSurface) {
        model.runReviewAction(action, workspaceRoot: model.activeWorkspaceRoot ?? workspaceRoot)
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
    }

    private func persistConfig() {
        try? bootstrap.saveConfig(model.root.config)
    }

    func openCommandPalette() {
        isCommandPalettePresented = true
    }
}

private extension Notification.Name {
    static let quillCodeNewChat = Notification.Name("QuillCodeNewChat")
    static let quillCodeOpenProject = Notification.Name("QuillCodeOpenProject")
    static let quillCodeCommandPalette = Notification.Name("QuillCodeCommandPalette")
    static let quillCodeToggleTerminal = Notification.Name("QuillCodeToggleTerminal")
}
