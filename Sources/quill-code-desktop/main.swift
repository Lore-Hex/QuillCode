import SwiftUI
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
            onSend: controller.send,
            onSelectThread: controller.selectThread,
            onSetMode: controller.setMode,
            onSetModel: controller.setModel,
            onCommand: controller.runCommand
        )
        .onReceive(NotificationCenter.default.publisher(for: .quillCodeNewChat)) { _ in
            controller.newChat()
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
        self.surface = model.surface()
        self.draft = model.composer.draft
    }

    func newChat() {
        _ = model.newChat()
        refresh()
    }

    func selectThread(_ id: UUID) {
        model.selectThread(id)
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

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        model.setDraft(prompt)
        draft = ""
        refresh()
        Task {
            await model.submitComposer(workspaceRoot: workspaceRoot)
            refresh()
        }
    }

    func runCommand(_ command: WorkspaceCommandSurface) {
        switch command.id {
        case "new-chat":
            newChat()
        case "stop-all":
            break
        default:
            break
        }
    }

    private func refresh() {
        surface = model.surface()
        if draft != model.composer.draft, !model.composer.isSending {
            draft = model.composer.draft
        }
    }

    private func persistConfig() {
        try? bootstrap.saveConfig(model.root.config)
    }
}

private extension Notification.Name {
    static let quillCodeNewChat = Notification.Name("QuillCodeNewChat")
}
