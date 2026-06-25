import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

@MainActor
public final class QuillCodeWorkspaceModel {
    public internal(set) var root: QuillCodeRootState
    public internal(set) var composer: ComposerState
    public internal(set) var terminal: TerminalState
    public private(set) var browser: BrowserState
    public internal(set) var extensions: ExtensionsState
    public private(set) var memories: MemoriesState
    public private(set) var activity: ActivityState
    public private(set) var automations: AutomationsState
    public internal(set) var sidebarSelection: SidebarSelectionState
    public private(set) var lastError: String?

    private var runner: AgentRunner
    let threadPersistence: WorkspaceThreadPersistence
    private let projectStore: JSONProjectStore?
    private let automationStore: JSONAutomationStore?
    private let globalMemoryDirectory: URL?
    private var computerUseBackend: (any ComputerUseBackend)?
    let sshRemoteShellExecutor: SSHRemoteShellExecutor
    let mcpRuntime: WorkspaceMCPRuntime

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

    func syncTerminalSessionToSelectedProject() {
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

    func appendNotice(_ summary: String) {
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

    func mutateSelectedThread(_ update: (inout ChatThread) -> Void) {
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

    func validThreadIDs() -> Set<UUID> {
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

    func touchProject(_ id: UUID?) {
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

    func saveProjects() {
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

}
