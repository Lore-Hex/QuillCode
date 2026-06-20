import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence

public enum ToolCardStatus: String, Codable, Sendable, Hashable {
    case queued
    case running
    case done
    case failed
    case review
}

public struct ToolCardState: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var status: ToolCardStatus
    public var inputJSON: String?
    public var outputJSON: String?
    public var isExpanded: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        status: ToolCardStatus,
        inputJSON: String? = nil,
        outputJSON: String? = nil,
        isExpanded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.isExpanded = isExpanded
    }
}

public struct ComposerState: Sendable, Hashable {
    public var draft: String
    public var isSending: Bool
    public var placeholder: String

    public init(
        draft: String = "",
        isSending: Bool = false,
        placeholder: String = "Message QuillCode"
    ) {
        self.draft = draft
        self.isSending = isSending
        self.placeholder = placeholder
    }
}

@MainActor
public final class QuillCodeWorkspaceModel {
    public private(set) var root: QuillCodeRootState
    public private(set) var composer: ComposerState
    public private(set) var lastError: String?

    private let runner: AgentRunner
    private let threadStore: JSONThreadStore?

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        composer: ComposerState = ComposerState(),
        runner: AgentRunner = AgentRunner(),
        threadStore: JSONThreadStore? = nil
    ) {
        self.root = root
        self.composer = composer
        self.runner = runner
        self.threadStore = threadStore
        refreshTopBar()
    }

    public var selectedThread: ChatThread? {
        guard let selectedThreadID = root.selectedThreadID else { return nil }
        return root.threads.first { $0.id == selectedThreadID }
    }

    public var selectedProject: ProjectRef? {
        guard let selectedProjectID = root.selectedProjectID else { return nil }
        return root.projects.first { $0.id == selectedProjectID }
    }

    public var activeWorkspaceRoot: URL? {
        selectedProject.map { URL(fileURLWithPath: $0.path) }
    }

    public var currentToolCards: [ToolCardState] {
        selectedThread.map(Self.toolCards(for:)) ?? []
    }

    public func setDraft(_ draft: String) {
        composer.draft = draft
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        let thread = ChatThread(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel
        )
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = effectiveProjectID
        touchProject(effectiveProjectID)
        refreshTopBar(agentStatus: "Idle")
        return thread.id
    }

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        touchProject(root.selectedProjectID)
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let standardized = path.standardizedFileURL
        let projectName = name ?? Self.defaultProjectName(for: standardized)
        if let index = root.projects.firstIndex(where: { $0.path == standardized.path }) {
            root.projects[index].name = projectName
            root.projects[index].lastOpenedAt = Date()
            root.selectedProjectID = root.projects[index].id
            refreshTopBar(agentStatus: "Idle")
            return root.projects[index].id
        }

        let project = ProjectRef(name: projectName, path: standardized.path)
        root.projects.insert(project, at: 0)
        root.selectedProjectID = project.id
        refreshTopBar(agentStatus: "Idle")
        return project.id
    }

    public func selectProject(_ id: UUID?) {
        if let id {
            guard root.projects.contains(where: { $0.id == id }) else { return }
        }
        root.selectedProjectID = id
        touchProject(id)
        root.selectedThreadID = root.threads
            .filter { !$0.isArchived && $0.projectID == id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .id
        refreshTopBar(agentStatus: "Idle")
    }

    public func togglePinSelectedThread() {
        mutateSelectedThread { thread in
            thread.isPinned.toggle()
        }
    }

    public func archiveSelectedThread() {
        mutateSelectedThread { thread in
            thread.isArchived = true
        }
        if selectedThread?.isArchived == true {
            root.selectedThreadID = root.threads.first(where: { !$0.isArchived })?.id
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func setMode(_ mode: AgentMode) {
        root.config.mode = mode
        mutateSelectedThread { thread in
            thread.mode = mode
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func setModel(_ model: String) {
        root.config.defaultModel = model
        mutateSelectedThread { thread in
            thread.model = model
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func setModelCatalog(_ models: [ModelInfo]) {
        guard !models.isEmpty else { return }
        root.modelCatalog = models
    }

    public func submitComposer(workspaceRoot: URL) async {
        let prompt = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return }

        composer.draft = ""
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        do {
            let result = try await runner.send(prompt, in: thread, workspaceRoot: workspaceRoot)
            thread = result.thread
            replaceThread(thread)
            try threadStore?.save(thread)
            composer.isSending = false
            refreshTopBar(agentStatus: "Idle")
        } catch {
            composer.isSending = false
            lastError = String(describing: error)
            refreshTopBar(agentStatus: "Failed")
        }
    }

    public static func toolCards(for thread: ChatThread) -> [ToolCardState] {
        var cards: [ToolCardState] = []

        for event in thread.events {
            switch event.kind {
            case .toolQueued:
                let call = decode(ToolCall.self, event.payloadJSON)
                cards.append(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
            case .toolRunning:
                updateLastOpenCard(&cards, status: .running, subtitle: "Running")
            case .toolCompleted:
                updateLastOpenCard(
                    &cards,
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateLastOpenCard(
                    &cards,
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                cards.append(ToolCardState(
                    id: event.id.uuidString,
                    title: "Safety Check",
                    subtitle: event.summary,
                    status: .review,
                    inputJSON: event.payloadJSON,
                    isExpanded: true
                ))
            case .message, .approvalDecided, .notice:
                continue
            }
        }

        return cards
    }

    private func mutateSelectedThread(_ update: (inout ChatThread) -> Void) {
        guard let selectedThreadID = root.selectedThreadID,
              let index = root.threads.firstIndex(where: { $0.id == selectedThreadID })
        else {
            return
        }
        update(&root.threads[index])
        root.threads[index].updatedAt = Date()
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    private func replaceThread(_ thread: ChatThread) {
        if let index = root.threads.firstIndex(where: { $0.id == thread.id }) {
            root.threads[index] = thread
        } else {
            root.threads.insert(thread, at: 0)
        }
        root.selectedThreadID = thread.id
        root.selectedProjectID = knownProjectID(thread.projectID)
        touchProject(root.selectedProjectID)
    }

    private func refreshTopBar(agentStatus: String? = nil) {
        let thread = selectedThread
        let projectID = thread?.projectID ?? root.selectedProjectID
        let project = projectID.flatMap { id in root.projects.first { $0.id == id } }
        root.topBar = TopBarState(
            projectName: project?.name,
            threadTitle: thread?.title,
            model: thread?.model ?? root.config.defaultModel,
            mode: thread?.mode ?? root.config.mode,
            agentStatus: agentStatus ?? root.topBar.agentStatus,
            computerUseStatus: root.topBar.computerUseStatus
        )
    }

    private func touchProject(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        root.projects[index].lastOpenedAt = Date()
    }

    private func knownProjectID(_ id: UUID?) -> UUID? {
        guard let id, root.projects.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private static func defaultProjectName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    private static func updateLastOpenCard(
        _ cards: inout [ToolCardState],
        status: ToolCardStatus,
        subtitle: String,
        outputJSON: String? = nil
    ) {
        guard let index = cards.lastIndex(where: { $0.status == .queued || $0.status == .running }) else {
            cards.append(ToolCardState(
                id: "tool-\(UUID().uuidString)",
                title: "Tool",
                subtitle: subtitle,
                status: status,
                outputJSON: outputJSON
            ))
            return
        }
        cards[index].status = status
        cards[index].subtitle = subtitle
        if let outputJSON {
            cards[index].outputJSON = outputJSON
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
