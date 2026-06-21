import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

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

public struct TerminalCommandState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var ok: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.ok = ok
        self.createdAt = createdAt
    }
}

public struct WorkspaceWorktreeCreateRequest: Sendable, Hashable {
    public var path: String
    public var branch: String
    public var base: String

    public init(path: String, branch: String = "", base: String = "") {
        self.path = path
        self.branch = branch
        self.base = base
    }
}

public struct WorkspaceWorktreeRemoveRequest: Sendable, Hashable {
    public var path: String
    public var force: Bool

    public init(path: String, force: Bool = false) {
        self.path = path
        self.force = force
    }
}

public struct TerminalState: Sendable, Hashable {
    public var isVisible: Bool
    public var draft: String
    public var isRunning: Bool
    public var entries: [TerminalCommandState]

    public init(
        isVisible: Bool = false,
        draft: String = "",
        isRunning: Bool = false,
        entries: [TerminalCommandState] = []
    ) {
        self.isVisible = isVisible
        self.draft = draft
        self.isRunning = isRunning
        self.entries = entries
    }
}

public struct BrowserCommentState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), url: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

public struct WorkspaceReviewCommentState: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var text: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.text = text
        self.createdAt = createdAt
    }
}

public struct BrowserState: Sendable, Hashable {
    public var isVisible: Bool
    public var addressDraft: String
    public var currentURL: String?
    public var title: String
    public var status: String
    public var comments: [BrowserCommentState]

    public init(
        isVisible: Bool = false,
        addressDraft: String = "",
        currentURL: String? = nil,
        title: String = "Browser preview",
        status: String = "Ready",
        comments: [BrowserCommentState] = []
    ) {
        self.isVisible = isVisible
        self.addressDraft = addressDraft
        self.currentURL = currentURL
        self.title = title
        self.status = status
        self.comments = comments
    }
}

@MainActor
public final class QuillCodeWorkspaceModel {
    public private(set) var root: QuillCodeRootState
    public private(set) var composer: ComposerState
    public private(set) var terminal: TerminalState
    public private(set) var browser: BrowserState
    public private(set) var lastError: String?

    private var runner: AgentRunner
    private let threadStore: JSONThreadStore?
    private let projectStore: JSONProjectStore?

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        composer: ComposerState = ComposerState(),
        terminal: TerminalState = TerminalState(),
        browser: BrowserState = BrowserState(),
        runner: AgentRunner = AgentRunner(),
        threadStore: JSONThreadStore? = nil,
        projectStore: JSONProjectStore? = nil
    ) {
        self.root = root
        self.composer = composer
        self.terminal = terminal
        self.browser = browser
        self.runner = runner
        self.threadStore = threadStore
        self.projectStore = projectStore
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

    public func setTerminalDraft(_ draft: String) {
        terminal.draft = draft
    }

    public func setTerminalVisible(_ isVisible: Bool) {
        terminal.isVisible = isVisible
    }

    public func toggleTerminal() {
        terminal.isVisible.toggle()
    }

    public func setBrowserAddressDraft(_ draft: String) {
        browser.addressDraft = draft
    }

    public func toggleBrowser() {
        browser.isVisible.toggle()
    }

    @discardableResult
    public func openBrowserPreview(_ input: String? = nil, workspaceRoot: URL? = nil) -> Bool {
        let rawValue = input ?? browser.addressDraft
        guard let url = Self.normalizedBrowserURL(rawValue, workspaceRoot: workspaceRoot) else {
            browser.isVisible = true
            browser.status = "Invalid address"
            lastError = "Enter an http, https, file, localhost, or project file URL."
            refreshTopBar(agentStatus: "Idle")
            return false
        }

        browser.isVisible = true
        browser.currentURL = url.absoluteString
        browser.addressDraft = url.absoluteString
        browser.title = Self.browserTitle(for: url)
        browser.status = "Preview ready"
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = browser.currentURL else {
            return false
        }
        browser.comments.append(BrowserCommentState(url: url, text: trimmed))
        browser.status = "Comment added"
        return true
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectInstructions(effectiveProjectID)
        let thread = ChatThread(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: effectiveProjectID)
        )
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = effectiveProjectID
        touchProject(effectiveProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return thread.id
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let copiedMessages = Self.forkSeedMessages(from: source.messages)
        let fork = ChatThread(
            title: "Fork: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Forked from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions
        )
        root.threads.insert(fork, at: 0)
        root.selectedThreadID = fork.id
        root.selectedProjectID = knownProjectID(source.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(fork)
        refreshTopBar(agentStatus: "Idle")
        return fork.id
    }

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let standardized = path.standardizedFileURL
        let projectName = name ?? Self.defaultProjectName(for: standardized)
        if let index = root.projects.firstIndex(where: { $0.path == standardized.path }) {
            root.projects[index].name = projectName
            root.projects[index].instructions = ProjectInstructionLoader.load(from: standardized)
            root.projects[index].localActions = LocalEnvironmentActionLoader.load(from: standardized)
            root.projects[index].lastOpenedAt = Date()
            root.selectedProjectID = root.projects[index].id
            saveProjects()
            refreshTopBar(agentStatus: "Idle")
            return root.projects[index].id
        }

        let project = ProjectRef(
            name: projectName,
            path: standardized.path,
            lastOpenedAt: Date(),
            instructions: ProjectInstructionLoader.load(from: standardized),
            localActions: LocalEnvironmentActionLoader.load(from: standardized)
        )
        root.projects.insert(project, at: 0)
        root.selectedProjectID = project.id
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return project.id
    }

    public func selectProject(_ id: UUID?) {
        if let id {
            guard root.projects.contains(where: { $0.id == id }) else { return }
        }
        root.selectedProjectID = id
        refreshProjectMetadata(id)
        touchProject(id)
        root.selectedThreadID = root.threads
            .filter { !$0.isArchived && $0.projectID == id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .id
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
    }

    public func togglePinSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        togglePinThread(selectedThreadID)
    }

    public func archiveSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        archiveThread(selectedThreadID)
    }

    public func togglePinThread(_ id: UUID) {
        mutateThread(id) { thread in
            thread.isPinned.toggle()
        }
    }

    public func archiveThread(_ id: UUID) {
        let archivedProjectID = root.threads.first { $0.id == id }?.projectID
        mutateThread(id) { thread in
            thread.isArchived = true
        }
        if root.selectedThreadID == id {
            root.selectedThreadID = root.threads
                .filter { !$0.isArchived && $0.projectID == archivedProjectID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?
                .id
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

    public func applySettings(config: AppConfig, trustedRouterAPIKeyConfigured: Bool) {
        root.config = config
        root.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured
        mutateSelectedThread { thread in
            thread.mode = config.mode
            thread.model = config.defaultModel
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func applyRuntime(_ runtime: QuillCodeRuntime) {
        runner = runtime.runner
        refreshTopBar(agentStatus: runtime.statusLabel)
    }

    public func setAgentStatus(_ status: String, lastError: String? = nil) {
        self.lastError = lastError
        refreshTopBar(agentStatus: status)
    }

    public func submitComposer(workspaceRoot: URL) async {
        let prompt = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if let command = SlashCommandParser.parse(prompt) {
            composer.draft = ""
            lastError = nil
            handleSlashCommand(command, originalPrompt: prompt)
            return
        }

        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return }
        syncInstructions(into: &thread)
        let threadID = thread.id

        composer.draft = ""
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        do {
            try Task.checkCancellation()
            let result = try await runner.send(
                prompt,
                in: thread,
                workspaceRoot: workspaceRoot,
                onProgress: { [weak self] progressThread in
                    await self?.applyAgentProgress(progressThread, expectedThreadID: threadID)
                }
            )
            try Task.checkCancellation()
            thread = result.thread
            replaceThread(thread)
            try threadStore?.save(thread)
            composer.isSending = false
            refreshTopBar(agentStatus: "Idle")
        } catch is CancellationError {
            finishCancelledSend(userPrompt: prompt, threadID: threadID)
        } catch {
            composer.isSending = false
            lastError = String(describing: error)
            refreshTopBar(agentStatus: "Failed")
        }
    }

    private func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard thread.id == expectedThreadID else { return }
        replaceThread(thread)
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: agentStatus(for: thread))
    }

    private func agentStatus(for thread: ChatThread) -> String {
        switch thread.events.last?.kind {
        case .toolQueued:
            return "Queued"
        case .toolRunning:
            return "Running"
        case .approvalRequested:
            return "Review"
        case .toolCompleted:
            return "Finishing"
        case .toolFailed:
            return "Failed"
        case .message, .approvalDecided, .reviewComment, .notice, .none:
            return "Running"
        }
    }

    public func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let actionCall = action.toolCall
        let actionResult = router.execute(actionCall)
        appendToolRun(call: actionCall, result: actionResult)

        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult = router.execute(diffCall)
        appendToolRun(call: diffCall, result: diffResult)

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: actionResult.ok && diffResult.ok ? "Idle" : "Failed")
    }

    @discardableResult
    public func addReviewComment(path: String, text: String) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedThread != nil,
              !trimmedPath.isEmpty,
              !trimmedText.isEmpty
        else {
            return false
        }

        let currentReview = surface().review
        guard currentReview.files.contains(where: { $0.path == trimmedPath }) else {
            return false
        }

        let comment = WorkspaceReviewCommentState(path: trimmedPath, text: trimmedText)
        let payloadJSON = (try? JSONHelpers.encodePretty(comment)) ?? "{}"
        mutateSelectedThread { thread in
            thread.events.append(.init(
                kind: .reviewComment,
                summary: "Commented on \(trimmedPath)",
                payloadJSON: payloadJSON
            ))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func runWorkspaceCommand(_ commandID: String, workspaceRoot: URL) -> Bool {
        if commandID.hasPrefix("local-env:") {
            return runLocalEnvironmentAction(commandID, workspaceRoot: workspaceRoot)
        }
        switch commandID {
        case "toggle-browser":
            toggleBrowser()
            return true
        case "fork-from-last":
            return forkFromLast() != nil
        case "git-worktree-list":
            runToolCall(
                ToolCall(name: ToolDefinition.gitWorktreeList.name, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
            return true
        case "git-pr-create":
            setDraft("Create a pull request titled ")
            return true
        case "git-worktree-create":
            setDraft("Create a git worktree named ")
            return true
        case "git-worktree-remove":
            setDraft("Remove git worktree at ")
            return true
        default:
            return false
        }
    }

    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = localAction(withID: actionID) else {
            return false
        }
        runToolCall(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: toolArgumentsJSON(["cmd": action.command])
            ),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    public func createWorktree(_ request: WorkspaceWorktreeCreateRequest, workspaceRoot: URL) {
        var arguments: [String: Any] = ["path": request.path]
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = request.base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            arguments["branch"] = branch
        }
        if !base.isEmpty {
            arguments["base"] = base
        }
        runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
    }

    public func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest, workspaceRoot: URL) {
        runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeRemove.name,
                argumentsJSON: toolArgumentsJSON([
                    "path": request.path,
                    "force": request.force
                ])
            ),
            workspaceRoot: workspaceRoot
        )
    }

    public func runToolCall(_ call: ToolCall, workspaceRoot: URL) {
        if selectedThread == nil {
            _ = newChat()
        }
        refreshProjectInstructions(root.selectedProjectID)
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        let result = ToolRouter(workspaceRoot: workspaceRoot).execute(call)
        appendToolRun(call: call, result: result)

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: result.ok ? "Idle" : "Failed")
    }

    public func runTerminalCommand(workspaceRoot: URL) async {
        await runTerminalCommand(terminal.draft, workspaceRoot: workspaceRoot)
    }

    public func runTerminalCommand(_ input: String, workspaceRoot: URL) async {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !terminal.isRunning else { return }

        terminal.draft = ""
        terminal.isVisible = true
        terminal.isRunning = true
        lastError = nil
        refreshTopBar(agentStatus: "Terminal")

        let result = await ShellToolExecutor().runCancellable(.init(command: command, cwd: workspaceRoot))
        guard !Task.isCancelled else {
            terminal.isRunning = false
            lastError = nil
            refreshTopBar(agentStatus: "Stopped")
            return
        }

        terminal.entries.append(TerminalCommandState(
            command: command,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            ok: result.ok
        ))
        terminal.isRunning = false
        refreshTopBar(agentStatus: result.ok ? "Idle" : "Failed")
    }

    public func cancelActiveWork() {
        let hadActiveWork = composer.isSending || terminal.isRunning
        composer.isSending = false
        terminal.isRunning = false
        lastError = nil
        if hadActiveWork {
            refreshTopBar(agentStatus: "Stopped")
        }
    }

    public static func toolCards(for thread: ChatThread) -> [ToolCardState] {
        var cards: [ToolCardState] = []
        var activeToolCardIndex: Int?

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolCardIndex else {
                return
            }
            updateCard(&cards, at: index, status: status, subtitle: subtitle, outputJSON: outputJSON)
            if status == .done || status == .failed {
                activeToolCardIndex = nil
            }
        }

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
                activeToolCardIndex = cards.count - 1
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
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
            case .message, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        return cards
    }

    public static func transcriptTimelineItems(for thread: ChatThread) -> [TranscriptTimelineItemSurface] {
        guard !thread.events.isEmpty else {
            return thread.messages.map(MessageSurface.init).map(TranscriptTimelineItemSurface.message)
                + toolCards(for: thread).map(TranscriptTimelineItemSurface.toolCard)
        }

        var consumedMessageIDs = Set<UUID>()
        var items: [TranscriptTimelineItemSurface] = []
        var activeToolItemIndex: Int?

        func appendMessage(matching summary: String) {
            guard let message = thread.messages.first(where: {
                !consumedMessageIDs.contains($0.id) && $0.content == summary
            }) else {
                return
            }
            consumedMessageIDs.insert(message.id)
            items.append(.message(MessageSurface(message: message)))
        }

        func appendToolCard(_ card: ToolCardState) {
            items.append(.toolCard(card))
            activeToolItemIndex = items.count - 1
        }

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolItemIndex,
                  var card = items[index].toolCard
            else {
                appendToolCard(ToolCardState(
                    id: "orphan-\(UUID().uuidString)",
                    title: "Tool",
                    subtitle: subtitle,
                    status: status,
                    outputJSON: outputJSON
                ))
                return
            }
            card.status = status
            card.subtitle = subtitle
            if let outputJSON {
                card.outputJSON = outputJSON
            }
            items[index] = .toolCard(card)
            if status == .done || status == .failed {
                activeToolItemIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .message:
                appendMessage(matching: event.summary)
            case .toolQueued:
                let call = decode(ToolCall.self, event.payloadJSON)
                appendToolCard(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                items.append(.toolCard(ToolCardState(
                    id: event.id.uuidString,
                    title: "Safety Check",
                    subtitle: event.summary,
                    status: .review,
                    inputJSON: event.payloadJSON,
                    isExpanded: true
                )))
            case .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        for message in thread.messages where !consumedMessageIDs.contains(message.id) {
            items.append(.message(MessageSurface(message: message)))
        }
        return items
    }

    private func appendToolRun(call: ToolCall, result: ToolResult) {
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? call.argumentsJSON
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        mutateSelectedThread { thread in
            thread.events.append(.init(
                kind: .toolQueued,
                summary: "\(call.name) queued",
                payloadJSON: callJSON
            ))
            thread.events.append(.init(
                kind: .toolRunning,
                summary: "\(call.name) running"
            ))
            thread.events.append(.init(
                kind: result.ok ? .toolCompleted : .toolFailed,
                summary: "\(call.name) \(result.ok ? "completed" : "failed")",
                payloadJSON: resultJSON
            ))
        }
    }

    private func toolArgumentsJSON(_ values: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String) {
        switch command {
        case .help:
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: """
                Slash commands:
                /new - start a new chat
                /status - show current project, mode, and model
                /mode auto|review|read-only - switch approval behavior
                /model provider/model - switch the active model
                """,
                title: "Slash commands"
            )
        case .status:
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: statusText(),
                title: "Status"
            )
        case .newChat:
            _ = newChat()
        case .mode(let mode):
            setMode(mode)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Mode set to \(Self.modeLabel(mode)).",
                title: "Set mode"
            )
        case .model(let model):
            setModel(model)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Model set to \(model).",
                title: "Set model"
            )
        case .invalid(let message):
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: message,
                title: "Slash command"
            )
        case .unknown(let name):
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Unknown slash command '/\(name)'. Try /help.",
                title: "Slash command"
            )
        }
        composer.isSending = false
        refreshTopBar(agentStatus: "Idle")
    }

    private func appendLocalCommandTranscript(userText: String, assistantText: String, title: String) {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = title
            }
            thread.messages.append(ChatMessage(role: .user, content: userText))
            thread.messages.append(ChatMessage(role: .assistant, content: assistantText))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
    }

    private func finishCancelledSend(userPrompt: String, threadID: UUID) {
        composer.isSending = false
        lastError = nil
        mutateThread(threadID) { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = Self.title(fromUserPrompt: userPrompt)
            }
            if !thread.messages.contains(where: { $0.role == .user && $0.content == userPrompt }) {
                thread.messages.append(ChatMessage(role: .user, content: userPrompt))
            }
            let summary = "Stopped by user"
            if thread.events.last?.kind != .notice || thread.events.last?.summary != summary {
                thread.events.append(.init(kind: .notice, summary: summary))
            }
        }
        refreshTopBar(agentStatus: "Stopped")
    }

    private static func title(fromUserPrompt userPrompt: String) -> String {
        let words = userPrompt.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }

    private static func forkSeedMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            return Array(messages.suffix(4))
        }
        return Array(messages[lastUserIndex...].prefix(4))
    }

    private func statusText() -> String {
        let project = selectedProject?.name ?? root.topBar.projectName ?? "No project"
        let thread = selectedThread?.title ?? "No chat"
        let instructionLabel = Self.instructionStatusLabel(for: selectedProject?.instructions ?? selectedThread?.instructions ?? [])
        return """
        Project: \(project)
        Thread: \(thread)
        Instructions: \(instructionLabel)
        Mode: \(Self.modeLabel(root.topBar.mode))
        Model: \(root.topBar.model)
        Agent: \(root.topBar.agentStatus)
        """
    }

    private func mutateSelectedThread(_ update: (inout ChatThread) -> Void) {
        guard let selectedThreadID = root.selectedThreadID,
              let index = mutateThread(selectedThreadID, update)
        else {
            return
        }
        root.selectedThreadID = root.threads[index].id
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    @discardableResult
    private func mutateThread(_ id: UUID, _ update: (inout ChatThread) -> Void) -> Int? {
        guard let index = root.threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        update(&root.threads[index])
        root.threads[index].updatedAt = Date()
        try? threadStore?.save(root.threads[index])
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return index
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
        saveProjects()
    }

    public func refreshSelectedProjectInstructions() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectInstructions(projectID)
        let refreshedInstructions = instructions(for: projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedInstructions
        }
        saveProjects()
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

    private func refreshProjectInstructions(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        root.projects[index].instructions = ProjectInstructionLoader.load(from: rootURL)
    }

    private func refreshProjectMetadata(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        root.projects[index].instructions = ProjectInstructionLoader.load(from: rootURL)
        root.projects[index].localActions = LocalEnvironmentActionLoader.load(from: rootURL)
    }

    private func syncInstructions(into thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectInstructions(projectID)
        thread.instructions = instructions(for: projectID)
    }

    private func instructions(for projectID: UUID?) -> [ProjectInstruction] {
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID })
        else {
            return []
        }
        return project.instructions
    }

    private func localAction(withID id: String) -> LocalEnvironmentAction? {
        selectedProject?.localActions.first { $0.id == id }
    }

    static func instructionStatusLabel(for instructions: [ProjectInstruction]) -> String {
        guard !instructions.isEmpty else { return "No project instructions" }
        let truncated = instructions.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(instructions.count) instruction file\(instructions.count == 1 ? "" : "s") loaded\(truncated)"
    }

    private func knownProjectID(_ id: UUID?) -> UUID? {
        guard let id, root.projects.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func saveProjects() {
        try? projectStore?.save(root.projects)
    }

    private static func defaultProjectName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    private static func normalizedBrowserURL(_ rawValue: String, workspaceRoot: URL?) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return url
        }

        if trimmed.hasPrefix("localhost")
            || trimmed.hasPrefix("127.0.0.1")
            || trimmed.hasPrefix("[::1]") {
            return URL(string: "http://\(trimmed)")
        }

        if let workspaceRoot,
           let fileURL = projectFileBrowserURL(trimmed, workspaceRoot: workspaceRoot) {
            return fileURL
        }

        if trimmed.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL.standardizedFileURL
            }
        }

        if trimmed.contains(".") {
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }

    private static func projectFileBrowserURL(_ relativePath: String, workspaceRoot: URL) -> URL? {
        guard !relativePath.contains("..") else { return nil }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard (fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/")),
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return nil
        }
        return fileURL
    }

    private static func browserTitle(for url: URL) -> String {
        if url.isFileURL {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return url.host ?? url.absoluteString
    }

    private static func updateCard(
        _ cards: inout [ToolCardState],
        at index: Int,
        status: ToolCardStatus,
        subtitle: String,
        outputJSON: String? = nil
    ) {
        guard cards.indices.contains(index) else { return }
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

private extension WorkspaceReviewActionSurface {
    var toolCall: ToolCall {
        switch kind {
        case .stage:
            return ToolCall(
                name: ToolDefinition.gitStage.name,
                argumentsJSON: ToolArguments.json(["path": path])
            )
        case .restore:
            return ToolCall(
                name: ToolDefinition.gitRestore.name,
                argumentsJSON: ToolArguments.json(["path": path])
            )
        case .stageHunk:
            return ToolCall(
                name: ToolDefinition.gitStageHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": path,
                    "patch": patch ?? ""
                ])
            )
        case .restoreHunk:
            return ToolCall(
                name: ToolDefinition.gitRestoreHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": path,
                    "patch": patch ?? ""
                ])
            )
        }
    }
}
