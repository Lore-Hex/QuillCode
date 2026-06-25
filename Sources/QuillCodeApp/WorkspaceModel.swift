import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

@MainActor
public final class QuillCodeWorkspaceModel {
    public private(set) var root: QuillCodeRootState
    public private(set) var composer: ComposerState
    public private(set) var terminal: TerminalState
    public private(set) var browser: BrowserState
    public private(set) var extensions: ExtensionsState
    public private(set) var memories: MemoriesState
    public private(set) var activity: ActivityState
    public private(set) var automations: AutomationsState
    public private(set) var sidebarSelection: SidebarSelectionState
    public private(set) var lastError: String?

    private var runner: AgentRunner
    private let threadPersistence: WorkspaceThreadPersistence
    private let projectStore: JSONProjectStore?
    private let automationStore: JSONAutomationStore?
    private let globalMemoryDirectory: URL?
    private var computerUseBackend: (any ComputerUseBackend)?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor
    private let mcpRuntime: WorkspaceMCPRuntime

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        composer: ComposerState = ComposerState(),
        terminal: TerminalState = TerminalState(),
        browser: BrowserState = BrowserState(),
        extensions: ExtensionsState = ExtensionsState(),
        memories: MemoriesState = MemoriesState(),
        activity: ActivityState = ActivityState(),
        automations: AutomationsState = AutomationsState(),
        sidebarSelection: SidebarSelectionState = SidebarSelectionState(),
        runner: AgentRunner = AgentRunner(),
        threadStore: JSONThreadStore? = nil,
        projectStore: JSONProjectStore? = nil,
        automationStore: JSONAutomationStore? = nil,
        globalMemoryDirectory: URL? = nil,
        computerUseBackend: (any ComputerUseBackend)? = nil,
        sshRemoteShellExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor()
    ) {
        self.root = root
        self.composer = composer
        self.terminal = terminal
        self.browser = browser
        self.extensions = extensions
        self.memories = memories
        self.activity = activity
        self.automations = automations
        self.sidebarSelection = sidebarSelection
        self.runner = runner
        self.threadPersistence = WorkspaceThreadPersistence(store: threadStore)
        self.projectStore = projectStore
        self.automationStore = automationStore
        self.globalMemoryDirectory = globalMemoryDirectory
        self.computerUseBackend = computerUseBackend
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.mcpRuntime = WorkspaceMCPRuntime()
        if let computerUseBackend {
            self.root.topBar.computerUseStatus = computerUseBackend.status
        }
        syncTerminalSessionToSelectedProject()
        refreshTopBar()
    }

    deinit {
        mcpRuntime.terminateAllRunningProcesses()
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
        guard let selectedProject, !selectedProject.isRemote else { return nil }
        return URL(fileURLWithPath: selectedProject.path)
    }

    var terminalCurrentDirectoryURL: URL? {
        WorkspaceTerminalEngine.currentDirectoryURL(
            terminal: terminal,
            selectedProjectID: knownProjectID(root.selectedProjectID),
            selectedProjectIsRemote: selectedProject?.isRemote == true,
            activeWorkspaceRoot: activeWorkspaceRoot
        )
    }

    private func syncTerminalSessionToSelectedProject() {
        WorkspaceTerminalEngine.syncSessionToSelectedProject(
            terminal: &terminal,
            selectedProjectID: knownProjectID(root.selectedProjectID),
            selectedProjectDisplayPath: selectedProject?.displayPath
        )
    }

    func mutateBrowserState<Result>(
        _ mutation: (inout BrowserState, inout String?) -> Result
    ) -> Result {
        mutation(&browser, &lastError)
    }

    public var currentToolCards: [ToolCardState] {
        guard let selectedThread else { return [] }
        let cards = WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards()
        return executionContextSurfaceBuilder.enrichToolCards(cards, for: selectedThread)
    }

    public var currentTimelineItems: [TranscriptTimelineItemSurface] {
        guard let selectedThread else { return [] }
        let items = WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).timelineItems()
        return executionContextSurfaceBuilder.enrichTimelineItems(items, for: selectedThread)
    }

    private var executionContextSurfaceBuilder: WorkspaceExecutionContextSurfaceBuilder {
        WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: selectedProject,
            projects: root.projects
        )
    }

    private var contextResolver: WorkspaceContextResolver {
        WorkspaceContextResolver(
            projects: root.projects,
            globalMemories: root.globalMemories,
            selectedProject: selectedProject
        )
    }

    func project(id: UUID) -> ProjectRef? {
        root.projects.first { $0.id == id }
    }

    public var canRetryLastUserTurn: Bool {
        WorkspaceRetryPlanner.canRetryLastUserTurn(
            in: selectedThread,
            isSending: composer.isSending
        )
    }

    public func setDraft(_ draft: String) {
        composer.draft = draft
    }

    @discardableResult
    public func setMessageFeedback(messageID: UUID, value: MessageFeedbackValue) -> Bool {
        guard selectedThread?.messages.contains(where: { $0.id == messageID && $0.role == .assistant }) == true else {
            return false
        }
        let feedback = MessageFeedback(messageID: messageID, value: value)
        guard let payloadJSON = try? JSONHelpers.encodePretty(feedback) else {
            return false
        }
        let summary: String
        switch value {
        case .helpful:
            summary = "Marked assistant response helpful"
        case .notHelpful:
            summary = "Marked assistant response not helpful"
        }
        mutateSelectedThread { thread in
            thread.events.append(ThreadEvent(
                kind: .messageFeedback,
                summary: summary,
                payloadJSON: payloadJSON
            ))
        }
        return true
    }

    @discardableResult
    public func prepareRetryLastUserTurn() -> Bool {
        guard let draft = WorkspaceRetryPlanner.retryDraft(in: selectedThread) else {
            return false
        }
        composer.draft = draft
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
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

    @discardableResult
    public func clearTerminalHistory() -> Bool {
        guard WorkspaceTerminalEngine.clearHistory(terminal: &terminal) else { return false }
        terminal.isVisible = true
        lastError = nil
        return true
    }

    public func toggleExtensions() {
        extensions.isVisible.toggle()
    }

    public func toggleMemories() {
        memories.isVisible.toggle()
    }

    public func toggleActivity() {
        activity.isVisible.toggle()
    }

    public func toggleAutomations() {
        automations.isVisible.toggle()
    }

    public func toggleActivitySection(_ section: ActivitySectionKind) {
        activity.isVisible = true
        if activity.collapsedSectionIDs.contains(section) {
            activity.collapsedSectionIDs.remove(section)
        } else {
            activity.collapsedSectionIDs.insert(section)
        }
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let thread = WorkspaceThreadCreationEngine.newThread(context: WorkspaceProjectContextRefresher.threadCreationContext(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        ))
        return insertCreatedThread(thread, selectedProjectID: effectiveProjectID, saveThread: false)
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let projectID = knownProjectID(source.projectID)
        let fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: projectID
        )
        return insertCreatedThread(fork, selectedProjectID: projectID, saveThread: true)
    }

    @discardableResult
    public func compactContext() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let projectID = knownProjectID(source.projectID)
        let compacted = WorkspaceThreadCreationEngine.compactThread(
            from: source,
            projectID: projectID
        )
        return insertCreatedThread(compacted, selectedProjectID: projectID, saveThread: true)
    }

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    public func startSidebarSelection(selecting id: UUID? = nil) {
        sidebarSelection = WorkspaceSidebarSelectionEngine.start(
            selecting: id,
            state: sidebarSelection,
            validThreadIDs: validThreadIDs()
        )
    }

    public func clearSidebarSelection() {
        sidebarSelection = WorkspaceSidebarSelectionEngine.clear()
    }

    public func selectAllSidebarThreads() {
        sidebarSelection = WorkspaceSidebarSelectionEngine.selectAll(
            orderedThreadIDs: root.allSidebarItems.map(\.id)
        )
    }

    public func toggleSidebarThreadSelection(_ id: UUID) {
        guard let nextSelection = WorkspaceSidebarSelectionEngine.toggle(
            id,
            state: sidebarSelection,
            validThreadIDs: validThreadIDs()
        ) else { return }
        sidebarSelection = nextSelection
    }

    @discardableResult
    public func performSidebarBulkAction(_ kind: SidebarBulkActionKind) -> Bool {
        guard let plan = WorkspaceSidebarBulkActionPlanner.plan(
            kind: kind,
            selection: sidebarSelection,
            orderedSidebarThreadIDs: root.allSidebarItems.map(\.id),
            threads: root.threads,
            selectedThreadID: root.selectedThreadID
        ) else {
            return false
        }
        guard let result = WorkspaceSidebarBulkActionExecutor.execute(
            plan,
            threads: root.threads,
            projects: root.projects,
            selectedThreadID: root.selectedThreadID,
            selectedProjectID: root.selectedProjectID
        ) else {
            return false
        }

        sidebarSelection = result.nextSelection
        root.threads = result.threads
        root.selectedThreadID = result.selectedThreadID
        root.selectedProjectID = result.selectedProjectID
        threadPersistence.save(result.changedThreads)
        for thread in result.removedThreads {
            threadPersistence.delete(thread.id)
        }
        if result.shouldSyncTerminalSession {
            syncTerminalSessionToSelectedProject()
        }
        if let projectID = result.projectIDToTouch {
            touchProject(projectID)
        }
        if result.shouldSaveProjects {
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        }
        return true
    }

    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let standardized = path.standardizedFileURL
        let result = WorkspaceProjectEngine.upsertLocalProject(
            path: standardized,
            name: name,
            metadata: WorkspaceProjectMetadataLoader.loadLocal(from: standardized),
            projects: &root.projects
        )
        root.selectedProjectID = result.projectID
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return result.projectID
    }

    @discardableResult
    public func addSSHProject(_ address: String, name: String? = nil) -> UUID? {
        switch WorkspaceProjectEngine.upsertSSHProject(address: address, name: name, projects: &root.projects) {
        case .failure(let error):
            lastError = error.message
            return nil
        case .success(let result):
            root.selectedProjectID = result.projectID
            syncTerminalSessionToSelectedProject()
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return result.projectID
        }
    }

    public func selectProject(_ id: UUID?) {
        guard let selection = WorkspaceProjectEngine.selectionAfterSelectingProject(
            id,
            projects: root.projects,
            threads: root.threads
        ) else { return }
        root.selectedProjectID = selection.projectID
        syncTerminalSessionToSelectedProject()
        refreshProjectMetadata(selection.projectID)
        touchProject(selection.projectID)
        root.selectedThreadID = selection.threadID
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    public func renameProject(_ id: UUID, to name: String) -> Bool {
        guard WorkspaceProjectEngine.renameProject(id, to: name, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func refreshProjectContext(_ id: UUID) -> Bool {
        guard let project = root.projects.first(where: { $0.id == id }) else {
            return false
        }
        if project.isRemote {
            guard refreshRemoteProjectContext(id) else {
                return false
            }
        } else {
            refreshProjectMetadata(id)
        }
        if selectedThread?.projectID == id || root.selectedProjectID == id {
            let refreshedContext = workspaceThreadContext(id)
            mutateSelectedThread { thread in
                guard thread.projectID == id else { return }
                thread.instructions = refreshedContext.instructions
                thread.memories = refreshedContext.memories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Refreshed project context",
                    payloadJSON: id.uuidString
                ))
            }
        }
        touchProject(id)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func removeProject(_ id: UUID) -> Bool {
        var projects = root.projects
        var threads = root.threads
        guard let result = WorkspaceProjectEngine.removeProject(
            id,
            projects: &projects,
            threads: &threads,
            selectedProjectID: root.selectedProjectID
        ) else {
            return false
        }
        root.projects = projects
        root.threads = threads
        for threadID in result.changedThreadIDs {
            guard let thread = root.threads.first(where: { $0.id == threadID }) else { continue }
            threadPersistence.save(thread)
        }
        root.selectedProjectID = result.selectedProjectID
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    public func togglePinSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        togglePinThread(selectedThreadID)
    }

    public func archiveSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        archiveThread(selectedThreadID)
    }

    @discardableResult
    public func renameThread(_ id: UUID, to title: String) -> Bool {
        var threads = root.threads
        guard let changedThread = WorkspaceThreadLifecycleEngine.renameThread(
            id,
            to: title,
            threads: &threads
        ) else {
            return false
        }
        root.threads = threads
        threadPersistence.save(changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func duplicateThread(_ id: UUID) -> UUID? {
        guard let source = root.threads.first(where: { $0.id == id }) else { return nil }
        let projectID = knownProjectID(source.projectID)
        let duplicate = WorkspaceThreadCreationEngine.duplicateThread(
            source,
            projectID: projectID
        )
        return insertCreatedThread(duplicate, selectedProjectID: projectID, saveThread: true)
    }

    @discardableResult
    func insertCreatedThread(
        _ thread: ChatThread,
        selectedProjectID: UUID?,
        saveThread: Bool
    ) -> UUID {
        clearSidebarSelection()
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = selectedProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(selectedProjectID)
        saveProjects()
        if saveThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return thread.id
    }

    public func togglePinThread(_ id: UUID) {
        var threads = root.threads
        guard let changedThread = WorkspaceThreadLifecycleEngine.togglePinThread(
            id,
            threads: &threads
        ) else { return }
        root.threads = threads
        threadPersistence.save(changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    public func archiveThread(_ id: UUID) {
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.archiveThread(
            id,
            threads: &threads,
            selectedThreadID: root.selectedThreadID
        ) else { return }
        root.threads = threads
        root.selectedThreadID = result.selectedThreadID
        threadPersistence.save(result.changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    public func unarchiveThread(_ id: UUID) -> Bool {
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.unarchiveThread(
            id,
            threads: &threads
        ) else {
            return false
        }
        root.threads = threads
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(result.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        threadPersistence.save(result.changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func deleteThread(_ id: UUID) -> Bool {
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.deleteThread(
            id,
            threads: &threads,
            selectedThreadID: root.selectedThreadID
        ) else {
            return false
        }
        root.threads = threads
        threadPersistence.delete(id)
        root.selectedThreadID = result.selectedThreadID
        if let selectedThread {
            root.selectedProjectID = knownProjectID(selectedThread.projectID)
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    public func setMode(_ mode: AgentMode) {
        WorkspaceConfigurationEngine.setMode(mode, config: &root.config)
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setMode(mode, thread: &thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    public func setModel(_ model: String) -> String {
        let modelID = WorkspaceConfigurationEngine.setModel(model, config: &root.config)
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return modelID
    }

    public func toggleModelFavorite(_ model: String) {
        guard WorkspaceConfigurationEngine.toggleFavorite(model, config: &root.config) else { return }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setModelCatalog(_ models: [ModelInfo]) {
        guard let catalog = WorkspaceConfigurationEngine.normalizedCatalog(from: models) else { return }
        root.modelCatalog = catalog
    }

    public func applySettings(config: AppConfig, trustedRouterAPIKeyConfigured: Bool) {
        WorkspaceConfigurationEngine.applySettings(
            config,
            trustedRouterAPIKeyConfigured: trustedRouterAPIKeyConfigured,
            root: &root
        )
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.syncThread(&thread, to: config)
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
        let submissionPlan = WorkspaceComposerSubmissionPlanner.plan(draft: composer.draft)
        let prompt: String
        switch submissionPlan {
        case .ignore:
            return
        case .slash(let command, let originalPrompt):
            composer.draft = ""
            lastError = nil
            handleSlashCommand(command, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
            return
        case .agent(let plannedPrompt):
            prompt = plannedPrompt
        }

        guard let thread = prepareAgentSendThread() else { return }
        let sendStart = WorkspaceAgentSendStartPlanner.started(
            prompt: prompt,
            thread: thread,
            composer: composer
        )
        applyComposerSendLifecycle(sendStart.lifecycle)

        let session = agentSendSessionFactory(workspaceRoot: workspaceRoot)
            .makeSession(prompt: sendStart.prompt, thread: sendStart.thread)
        let outcome = await WorkspaceAgentSendTaskCoordinator(
            start: sendStart,
            session: session
        ).run { [weak self] progressThread in
            await self?.applyAgentProgress(progressThread, expectedThreadID: sendStart.threadID)
        }
        finishAgentSend(outcome)
    }

    private func prepareAgentSendThread() -> ChatThread? {
        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return nil }
        syncThreadContext(into: &thread)
        return thread
    }

    private func agentSendSessionFactory(workspaceRoot: URL) -> WorkspaceAgentSendSessionFactory {
        WorkspaceAgentSendSessionFactory(
            baseRunner: runner,
            selectedProject: selectedProject,
            browser: browser,
            browserToolOverride: WorkspaceBrowserAgentToolOverride.make { [weak self] call, workspaceRoot in
                guard let self else { return nil }
                return self.executeBrowserToolForAgent(call, workspaceRoot: workspaceRoot)
            },
            computerUseBackend: computerUseBackend,
            globalMemoryDirectory: globalMemoryDirectory,
            mcpToolDefinitions: mcpRuntime.toolDefinitions(
                manifests: selectedProject?.extensionManifests ?? [],
                extensions: extensions
            ),
            mcpToolExecutionOverride: mcpRuntime.executionOverride(extensions: extensions),
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            workspaceRoot: workspaceRoot
        )
    }

    private func finishCompletedSend(_ result: WorkspaceAgentSendSessionResult) throws {
        let completion = WorkspaceAgentSendTerminalPlanner.completed(
            result: result,
            composer: composer
        )
        var thread = completion.thread
        if completion.shouldRefreshMemoryContext {
            refreshThreadMemoryContext(&thread)
        }
        updateThreadFromAgentRun(thread)
        try threadPersistence.saveOrThrow(thread)
        applyComposerSendLifecycle(completion.lifecycle)
    }

    private func finishAgentSend(_ outcome: WorkspaceAgentSendTaskOutcome) {
        switch outcome {
        case .completed(let result):
            do {
                try finishCompletedSend(result)
            } catch {
                finishFailedSend(error)
            }
        case .cancelled(let cancellation):
            finishCancelledSend(
                userPrompt: cancellation.userPrompt,
                threadID: cancellation.threadID
            )
        case .failed(let error):
            finishFailedSend(error)
        }
    }

    private func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard let progress = WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: expectedThreadID,
            composer: composer
        ) else { return }
        updateThreadFromAgentRun(progress.thread)
        composer = progress.composer
        lastError = progress.lastError
        refreshTopBar(agentStatus: progress.agentStatus)
    }

    public func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let runPlan = WorkspaceReviewActionToolCallPlanner.runPlan(for: action)
        let result = WorkspaceReviewActionRunner(
            plan: runPlan,
            executor: workspaceToolCallExecutor(router: router)
        ).run()
        for recordedResult in result.recordedResults {
            appendToolRun(call: recordedResult.call, result: recordedResult.result)
        }

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: result.finalStatus)
    }

    @discardableResult
    public func runToolCardAction(_ action: ToolCardActionSurface, workspaceRoot: URL) -> Bool {
        guard let plan = WorkspaceApprovalActionPlanner.plan(action: action, thread: selectedThread) else {
            lastError = "Approval request is no longer available."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }

        if let composerDraft = plan.composerDraft {
            composer.draft = composerDraft
            lastError = nil
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        }

        if let decisionEvent = plan.decisionEvent {
            mutateSelectedThread { thread in
                thread.events.append(decisionEvent)
            }
        }

        if plan.shouldRunTool {
            _ = runToolCall(plan.request.toolCall, workspaceRoot: workspaceRoot)
        } else {
            if let assistantNotice = plan.assistantNotice {
                appendAssistantNotice(assistantNotice)
            }
            if let thread = selectedThread {
                threadPersistence.save(thread)
            }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        }
        return true
    }

    @discardableResult
    public func addReviewComment(path: String, text: String) -> Bool {
        addReviewComment(path: path, lineNumber: nil, endLineNumber: nil, lineKind: nil, text: text)
    }

    @discardableResult
    public func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) -> Bool {
        guard selectedThread != nil,
              let event = WorkspaceReviewCommentPlanner.event(
                path: path,
                lineNumber: lineNumber,
                endLineNumber: endLineNumber,
                lineKind: lineKind,
                text: text,
                review: surface().review
              )
        else {
            return false
        }
        mutateSelectedThread { thread in
            thread.events.append(event)
        }
        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    func startMCPServer(id: String, workspaceRoot: URL) -> Bool {
        guard let manifest = selectedProject?.extensionManifests.first(where: {
            $0.id == id && $0.kind == .mcpServer
        }) else {
            lastError = "MCP server manifest not found."
            return false
        }
        let result = mcpRuntime.startServer(
            manifest: manifest,
            workspaceRoot: workspaceRoot,
            extensions: &extensions
        ) { [weak self] id, terminationStatus in
            self?.finishMCPServerProcess(id: id, terminationStatus: terminationStatus)
        }
        lastError = result.errorMessage
        if let agentStatus = result.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
        if let notice = result.notice {
            appendNotice(notice)
        }
        return result.ok
    }

    @discardableResult
    func stopMCPServer(id: String) -> Bool {
        guard let manifest = selectedProject?.extensionManifests.first(where: {
            $0.id == id && $0.kind == .mcpServer
        }) else {
            lastError = "MCP server manifest not found."
            return false
        }

        let result = mcpRuntime.stopServer(manifest: manifest, extensions: &extensions)
        lastError = result.errorMessage
        if let agentStatus = result.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
        if let notice = result.notice {
            appendNotice(notice)
        }
        return result.ok
    }

    private func finishMCPServerProcess(id: String, terminationStatus: Int32) {
        let result = mcpRuntime.finishServer(
            id: id,
            terminationStatus: terminationStatus,
            extensions: &extensions
        )
        if let agentStatus = result.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
    }

    private func appendNotice(_ summary: String) {
        mutateSelectedThread { thread in
            WorkspaceThreadNoticeAppender.appendNotice(summary, to: &thread)
        }
    }

    @discardableResult
    func deleteGlobalMemory(id: String) -> Bool {
        guard let mutation = WorkspaceMemoryEngine.deleteGlobal(id: id, directory: globalMemoryDirectory) else {
            return false
        }
        applyGlobalMemoryMutation(mutation)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = contextResolver.selectedLocalAction(withID: actionID) else {
            return false
        }
        runToolCall(
            WorkspaceShellToolCallPlanner.localEnvironmentAction(action),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    @discardableResult
    public func runProjectExtensionUpdate(id: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let manifest = selectedProject?.extensionManifests.first(where: { $0.id == id }),
              let toolCall = WorkspaceShellToolCallPlanner.projectExtensionUpdate(manifest)
        else {
            return false
        }

        let result = runToolCall(
            toolCall,
            workspaceRoot: workspaceRoot
        )
        refreshProjectMetadata(root.selectedProjectID)
        appendNotice(result.ok
            ? "Updated extension \(manifest.name)"
            : "Extension update failed for \(manifest.name)"
        )
        return result.ok
    }

    public func createWorktree(_ request: WorkspaceWorktreeCreateRequest, workspaceRoot: URL) {
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.create(request),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openToolResultWorktree(result) { projectID in
                worktreeOpenContext(projectID: projectID, request: request)
            }
        }
    }

    public func openWorktree(_ request: WorkspaceWorktreeOpenRequest, workspaceRoot: URL) {
        let result = runToolCall(
            WorkspaceWorktreeToolCallPlanner.open(request),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openToolResultWorktree(result) { projectID in
                worktreeOpenContext(projectID: projectID, request: request)
            }
        }
    }

    public func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest, workspaceRoot: URL) {
        runToolCall(
            WorkspaceWorktreeToolCallPlanner.remove(request),
            workspaceRoot: workspaceRoot
        )
    }

    @discardableResult
    public func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        if selectedThread == nil {
            _ = newChat()
        }
        guard selectedThread != nil else {
            return ToolResult(ok: false, error: "No active thread")
        }
        let contextProjectID = WorkspaceToolRunPreparer.effectiveProjectID(
            thread: selectedThread,
            fallbackProjectID: root.selectedProjectID
        )
        refreshProjectMetadata(contextProjectID)
        let fallbackProjectID = root.selectedProjectID
        let projects = root.projects
        let globalMemories = root.globalMemories
        mutateSelectedThread { thread in
            _ = WorkspaceToolRunPreparer.syncThreadContext(
                &thread,
                fallbackProjectID: fallbackProjectID,
                projects: projects,
                globalMemories: globalMemories
            )
        }
        let startPlan = WorkspaceToolRunLifecyclePlanner.started()
        lastError = startPlan.lastError
        refreshTopBar(agentStatus: startPlan.agentStatus)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let execution = workspaceToolCallExecutor(router: router).execute(
            call,
            browser: &browser,
            lastError: &lastError
        )
        let finishPlan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(execution: execution, to: &thread)
        }

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: finishPlan.agentStatus)
        return finishPlan.result
    }

    public func runTerminalCommand(workspaceRoot: URL) async {
        await runTerminalCommand(terminal.draft, workspaceRoot: workspaceRoot)
    }

    public func runTerminalCommand(_ input: String, workspaceRoot: URL) async {
        let command = WorkspaceTerminalEngine.normalizedCommand(input)
        guard WorkspaceTerminalEngine.canBeginRun(command: command, terminal: terminal) else { return }
        syncTerminalSessionToSelectedProject()

        let entryID = WorkspaceTerminalEngine.beginRun(command: command, terminal: &terminal)
        applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.started())

        guard let executionContext = WorkspaceTerminalEngine.executionContext(
            command: command,
            selectedProject: selectedProject,
            terminalCurrentDirectoryURL: terminalCurrentDirectoryURL,
            terminal: terminal,
            workspaceRoot: workspaceRoot,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        ) else {
            WorkspaceTerminalEngine.failMissingExecutionContext(id: entryID, terminal: &terminal)
            applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.missingExecutionContext())
            return
        }
        WorkspaceTerminalEngine.updateExecutionContext(
            id: entryID,
            executionContext: executionContext.surface,
            terminal: &terminal
        )

        var finalResult: ToolResult?
        for await event in ShellToolExecutor().runStreaming(executionContext.request) {
            if Task.isCancelled || WorkspaceTerminalEngine.entryIsStopped(id: entryID, terminal: terminal) {
                break
            }
            if let result = WorkspaceTerminalEngine.applyStreamingEvent(event, id: entryID, terminal: &terminal) {
                finalResult = result
            }
        }

        if WorkspaceTerminalEngine.entryIsStopped(id: entryID, terminal: terminal) {
            WorkspaceTerminalEngine.finishStoppedRun(executionContext: executionContext, terminal: &terminal)
            applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.stopped())
            return
        }
        guard !Task.isCancelled, let result = finalResult else {
            WorkspaceTerminalEngine.finishCancelledRun(
                id: entryID,
                executionContext: executionContext,
                terminal: &terminal
            )
            applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.cancelled())
            return
        }

        WorkspaceTerminalEngine.finishCompletedRun(
            id: entryID,
            executionContext: executionContext,
            result: result,
            terminal: &terminal
        )
        applyTerminalLifecyclePlan(WorkspaceTerminalLifecyclePlanner.finished(result: result))
    }

    private func applyTerminalLifecyclePlan(_ plan: WorkspaceTerminalLifecyclePlan) {
        lastError = plan.lastError
        refreshTopBar(agentStatus: plan.agentStatus)
    }

    public func cancelActiveWork() {
        applyActiveWorkStopPlan(
            WorkspaceActiveWorkStopPlanner.cancel(stoppedWork: stopActiveWorkspaceWork())
        )
    }

    @discardableResult
    public func disconnectAll() -> Bool {
        let stoppedWork = stopActiveWorkspaceWork()
        let shouldDetachRemoteProject = selectedProject?.isRemote == true

        guard let plan = WorkspaceActiveWorkStopPlanner.disconnectAll(
            stoppedWork: stoppedWork,
            shouldDetachRemoteProject: shouldDetachRemoteProject
        ) else {
            return false
        }

        if shouldDetachRemoteProject,
           let selection = WorkspaceProjectEngine.selectionAfterSelectingProject(
            nil,
            projects: root.projects,
            threads: root.threads
           ) {
            root.selectedProjectID = selection.projectID
            root.selectedThreadID = selection.threadID
            syncTerminalSessionToSelectedProject()
        }

        applyActiveWorkStopPlan(plan)
        return true
    }

    private func stopActiveWorkspaceWork() -> WorkspaceStoppedActiveWork {
        let hadRunningMCPServers = mcpRuntime.cancelAll(extensions: &extensions)
        let hadActiveWork = composer.isSending || terminal.isRunning
        composer.isSending = false
        terminal.isRunning = false
        WorkspaceTerminalEngine.stopRunningEntries(terminal: &terminal)
        return WorkspaceStoppedActiveWork(
            hadRunningMCPServers: hadRunningMCPServers,
            hadActiveWork: hadActiveWork
        )
    }

    private func applyActiveWorkStopPlan(_ plan: WorkspaceActiveWorkStopPlan) {
        lastError = plan.lastError
        if let agentStatus = plan.agentStatus {
            refreshTopBar(agentStatus: agentStatus)
        }
    }

    private func appendToolRun(call: ToolCall, result: ToolResult) {
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        }
    }

    private func openToolResultWorktree(
        _ result: ToolResult,
        context: (UUID) -> WorkspaceWorktreeOpenContext
    ) {
        guard let artifact = result.artifacts.first else { return }
        if selectedProject?.isRemote == true {
            openToolResultRemoteWorktree(artifact, context: context)
            return
        }
        let worktreeURL = URL(fileURLWithPath: artifact).standardizedFileURL
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return }

        let projectID = addProject(path: worktreeURL, name: Self.defaultProjectName(for: worktreeURL))
        refreshProjectMetadata(projectID)

        let opened = WorkspaceWorktreeOpenEngine.localThread(
            worktreeURL: worktreeURL,
            context: context(projectID)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func openToolResultRemoteWorktree(
        _ artifact: String,
        context: (UUID) -> WorkspaceWorktreeOpenContext
    ) {
        guard let connection = ProjectConnection.parseSSH(artifact),
              let projectID = addSSHProject(artifact, name: Self.defaultSSHProjectName(for: connection)) else {
            return
        }

        let opened = WorkspaceWorktreeOpenEngine.remoteThread(
            connection: connection,
            context: context(projectID)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeCreateRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceProjectContextRefresher.worktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeOpenRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceProjectContextRefresher.worktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func openCreatedWorktreeThread(_ thread: ChatThread, projectID: UUID) {
        _ = insertCreatedThread(thread, selectedProjectID: projectID, saveThread: true)
    }

    private func workspaceToolCallExecutor(router: ToolRouter) -> WorkspaceToolCallExecutor {
        WorkspaceToolCallExecutor(
            selectedProject: selectedProject,
            browser: browser,
            router: router,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    private func executeBrowserToolForAgent(_ call: ToolCall, workspaceRoot: URL) -> ToolResult? {
        let result = WorkspaceBrowserToolExecutor.execute(
            call,
            workspaceRoot: workspaceRoot,
            browser: &browser,
            lastError: &lastError
        )
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return result
    }

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) {
        let action = WorkspaceSlashCommandDispatchPlanner.action(
            for: command,
            userText: originalPrompt,
            statusText: statusText()
        )
        runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)
        composer.isSending = false
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    func runThreadFollowUpSlashCommand(_ scheduleText: String, originalPrompt: String) {
        appendScheduledAutomationTranscript(
            createThreadFollowUpAutomation(matching: scheduleText),
            success: {
                WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled(
                    userText: originalPrompt,
                    scheduleDescription: $0
                )
            },
            failure: {
                WorkspaceSlashCommandTranscriptPlanner.threadFollowUpFailed(
                    userText: originalPrompt,
                    message: $0
                )
            }
        )
    }

    func runWorkspaceScheduleSlashCommand(_ scheduleText: String, originalPrompt: String) {
        appendScheduledAutomationTranscript(
            createWorkspaceScheduleAutomation(matching: scheduleText),
            success: {
                WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled(
                    userText: originalPrompt,
                    scheduleDescription: $0
                )
            },
            failure: {
                WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleFailed(
                    userText: originalPrompt,
                    message: $0
                )
            }
        )
    }

    private func appendScheduledAutomationTranscript(
        _ automation: QuillAutomation?,
        success: (String) -> WorkspaceLocalCommandTranscript,
        failure: (String?) -> WorkspaceLocalCommandTranscript
    ) {
        let transcript = automation
            .map { success($0.scheduleDescription) }
            ?? failure(lastError)
        appendLocalCommandTranscript(transcript)
    }

    func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        let mutation = WorkspaceMemoryEngine.saveGlobal(
            content: content,
            userText: originalPrompt,
            directory: globalMemoryDirectory
        )
        applyGlobalMemoryMutation(mutation)
    }

    func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        let plan = WorkspaceEnvironmentSlashCommandPlanner.plan(
            query: query,
            userText: originalPrompt,
            actions: selectedProject?.localActions ?? []
        )
        switch plan {
        case .transcript(let transcript):
            appendLocalCommandTranscript(transcript)
        case .runAction(let actionID):
            _ = runLocalEnvironmentAction(actionID, workspaceRoot: workspaceRoot)
        }
    }

    func appendLocalCommandTranscript(_ transcript: WorkspaceLocalCommandTranscript) {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            WorkspaceLocalCommandTranscriptAppender.append(transcript, to: &thread)
        }
    }

    private func finishCancelledSend(userPrompt: String, threadID: UUID) {
        let terminal = WorkspaceAgentSendTerminalPlanner.cancelled(composer: composer)
        mutateThread(threadID) { thread in
            WorkspaceComposerCancellationPlanner.applyCancelledSend(userPrompt: userPrompt, to: &thread)
        }
        applyComposerSendLifecycle(terminal.lifecycle)
    }

    private func finishFailedSend(_ error: any Error) {
        let terminal = WorkspaceAgentSendTerminalPlanner.failed(error, composer: composer)
        applyComposerSendLifecycle(terminal.lifecycle)
    }

    private func applyComposerSendLifecycle(_ plan: WorkspaceComposerSendLifecyclePlan) {
        composer = plan.composer
        lastError = plan.lastError
        refreshTopBar(agentStatus: plan.agentStatus)
    }

    private func statusText() -> String {
        WorkspaceStatusTextBuilder.statusText(for: WorkspaceStatusContextBuilder.context(
            root: root,
            selectedProject: selectedProject,
            selectedThread: selectedThread,
            fallbackThreadContext: workspaceThreadContext(root.selectedProjectID)
        ))
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

    func selectedSidebarThreadIDs() -> [UUID] {
        let resolution = WorkspaceSidebarSelectionEngine.resolve(
            state: sidebarSelection,
            orderedSidebarThreadIDs: root.allSidebarItems.map(\.id),
            validThreadIDs: validThreadIDs()
        )
        sidebarSelection = resolution.state
        return resolution.selectedThreadIDs
    }

    private func validThreadIDs() -> Set<UUID> {
        Set(root.threads.map(\.id))
    }

    @discardableResult
    private func mutateThread(_ id: UUID, _ update: (inout ChatThread) -> Void) -> Int? {
        guard let index = threadPersistence.mutate(id, threads: &root.threads, update: update) else { return nil }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return index
    }

    private func updateThreadFromAgentRun(_ thread: ChatThread) {
        let result = WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate(
            thread,
            threads: &root.threads,
            projects: root.projects,
            selectedThreadID: root.selectedThreadID,
            selectedProjectID: root.selectedProjectID
        )
        root.selectedThreadID = result.selectedThreadID
        root.selectedProjectID = result.selectedProjectID
        if result.didSelectUpdatedThread {
            syncTerminalSessionToSelectedProject()
            touchProject(root.selectedProjectID)
            saveProjects()
        }
    }

    public func setComputerUseStatus(_ status: ComputerUseStatus) {
        root.topBar.computerUseStatus = status
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setComputerUseBackend(_ backend: any ComputerUseBackend) {
        computerUseBackend = backend
        setComputerUseStatus(backend.status)
    }

    public func refreshSelectedProjectInstructions() {
        refreshSelectedProjectContext()
    }

    public func refreshSelectedProjectContext() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        let refreshedContext = workspaceThreadContext(projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedContext.instructions
            thread.memories = refreshedContext.memories
        }
        saveProjects()
    }

    func refreshTopBar(agentStatus: String? = nil) {
        root.topBar = WorkspaceTopBarStateBuilder.state(from: root, agentStatus: agentStatus)
    }

    private func touchProject(_ id: UUID?) {
        WorkspaceProjectEngine.touchProject(id, projects: &root.projects)
    }

    func refreshProjectMetadata(_ id: UUID?) {
        refreshGlobalMemories()
        WorkspaceProjectContextRefresher.refreshLocalProjectMetadata(
            projectID: id,
            projects: &root.projects
        )
    }

    func workspaceThreadContext(_ projectID: UUID?) -> WorkspaceThreadContextSnapshot {
        WorkspaceProjectContextRefresher.threadContext(
            projectID: projectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    func refreshRemoteProjectContext(_ id: UUID) -> Bool {
        refreshGlobalMemories()
        do {
            let didRefresh = try WorkspaceProjectContextRefresher.refreshRemoteProjectContext(
                projectID: id,
                projects: &root.projects,
                executor: sshRemoteShellExecutor
            )
            if didRefresh {
                lastError = nil
            }
            return didRefresh
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func refreshGlobalMemories() {
        root.globalMemories = WorkspaceProjectContextRefresher.globalMemories(directory: globalMemoryDirectory)
    }

    private func applyGlobalMemoryMutation(_ mutation: WorkspaceMemoryMutation) {
        appendLocalCommandTranscript(mutation.transcript)
        if let updatedGlobalMemories = mutation.updatedGlobalMemories {
            root.globalMemories = updatedGlobalMemories
        }
        guard let summary = mutation.noticeSummary,
              let relativePath = mutation.noticeRelativePath
        else {
            return
        }
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        let refreshedContext = workspaceThreadContext(projectID)
        let update = WorkspaceMemoryEngine.contextUpdate(
            memories: refreshedContext.memories,
            summary: summary,
            relativePath: relativePath
        )
        mutateSelectedThread { thread in
            thread.memories = update.memories
            thread.events.append(update.event)
        }
    }

    private func syncThreadContext(into thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        WorkspaceProjectContextRefresher.syncThreadContext(
            &thread,
            fallbackProjectID: root.selectedProjectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    private func refreshThreadMemoryContext(_ thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        WorkspaceProjectContextRefresher.syncThreadMemories(
            &thread,
            fallbackProjectID: root.selectedProjectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }

    func knownProjectID(_ id: UUID?) -> UUID? {
        WorkspaceProjectEngine.knownProjectID(id, projects: root.projects)
    }

    private func saveProjects() {
        try? projectStore?.save(root.projects)
    }

    func applyAutomationState(_ state: AutomationsState) {
        automations = state
        saveAutomations()
    }

    func setAutomationsVisible(_ isVisible: Bool) {
        automations.isVisible = isVisible
    }

    func setLastError(_ message: String?) {
        lastError = message
    }

    private func saveAutomations() {
        try? automationStore?.save(automations.items)
    }

    private func appendAssistantNotice(_ text: String) {
        mutateSelectedThread { thread in
            WorkspaceThreadNoticeAppender.appendAssistantNotice(text, to: &thread)
        }
    }

    private static func defaultProjectName(for url: URL) -> String {
        WorkspaceProjectEngine.defaultProjectName(for: url)
    }

    private static func defaultSSHProjectName(for connection: ProjectConnection) -> String {
        WorkspaceProjectEngine.defaultSSHProjectName(for: connection)
    }

}
