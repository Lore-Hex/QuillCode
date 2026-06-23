import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

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

public struct MemoriesState: Sendable, Hashable {
    public var isVisible: Bool

    public init(isVisible: Bool = false) {
        self.isVisible = isVisible
    }
}

public struct ActivityState: Sendable, Hashable {
    public var isVisible: Bool
    public var collapsedSectionIDs: Set<ActivitySectionKind>

    public init(isVisible: Bool = false, collapsedSectionIDs: Set<ActivitySectionKind> = []) {
        self.isVisible = isVisible
        self.collapsedSectionIDs = collapsedSectionIDs
    }
}

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
    private let threadStore: JSONThreadStore?
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
        self.threadStore = threadStore
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

    private func project(id: UUID) -> ProjectRef? {
        root.projects.first { $0.id == id }
    }

    public var canRetryLastUserTurn: Bool {
        guard composer.isSending == false else { return false }
        return selectedThread?.messages.contains {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } == true
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
        guard let lastUserMessage = selectedThread?.messages.last(where: {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        composer.draft = lastUserMessage.content
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

    public func setBrowserAddressDraft(_ draft: String) {
        browser.addressDraft = draft
    }

    public func toggleBrowser() {
        browser.isVisible.toggle()
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

    public func setAutomations(_ items: [QuillAutomation]) {
        automations.items = QuillAutomation.sortedForDisplay(items)
        saveAutomations()
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        scheduleDescription: String = "Manual follow-up",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let thread = selectedThread else { return nil }
        let automation = WorkspaceAutomationFactory.threadFollowUp(
            for: thread,
            selectedProjectID: root.selectedProjectID,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        setAutomations(automations.items + [automation])
        automations.isVisible = true
        return automation
    }

    @discardableResult
    public func createThreadFollowUpAutomation(after seconds: TimeInterval, now: Date = Date()) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else { return nil }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            lastError = "Could not understand that follow-up schedule. Try `/follow-up in 30 minutes`, `/follow-up tomorrow at 9 AM`, or `/follow-up daily`."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningThreadFollowUpAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        scheduleDescription: String = "Manual workspace check",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let project = selectedProject else { return nil }
        let automation = WorkspaceAutomationFactory.workspaceSchedule(
            for: project,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        setAutomations(automations.items + [automation])
        automations.isVisible = true
        return automation
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(after seconds: TimeInterval, now: Date = Date()) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else { return nil }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            lastError = "Could not understand that workspace-check schedule. Try `/workspace-check in 1 hour`, `/workspace-check tomorrow at 9 AM`, or `/workspace-check every 2 hours`."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningWorkspaceScheduleAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

    public func updateAutomationStatus(id: UUID, status: QuillAutomationStatus) -> Bool {
        guard let index = automations.items.firstIndex(where: { $0.id == id }) else { return false }
        automations.items[index].status = status
        automations.items[index].updatedAt = Date()
        setAutomations(automations.items)
        return true
    }

    @discardableResult
    public func runAutomation(id: UUID) -> UUID? {
        runAutomationReport(id: id)?.followUpThreadID
    }

    @discardableResult
    public func runAutomationReport(id: UUID, now: Date = Date()) -> AutomationRunReport? {
        guard let automation = automations.items.first(where: { $0.id == id }) else { return nil }
        guard automation.status == .active else { return nil }

        switch automation.kind {
        case .threadFollowUp:
            return runThreadFollowUpAutomation(automation, now: now)
        case .workspaceSchedule:
            return runWorkspaceScheduleAutomation(automation, now: now)
        case .monitor:
            lastError = "Monitor automations can be configured, but monitor runners are not available yet."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }
    }

    @discardableResult
    public func runDueAutomations(now: Date = Date(), limit: Int = 5) -> [UUID] {
        runDueAutomationReports(now: now, limit: limit).map(\.followUpThreadID)
    }

    @discardableResult
    public func runDueAutomationReports(now: Date = Date(), limit: Int = 5) -> [AutomationRunReport] {
        let dueAutomationIDs = WorkspaceAutomationRunner.dueAutomationIDs(
            in: automations.items,
            now: now,
            limit: limit
        )
        return dueAutomationIDs.compactMap { runAutomationReport(id: $0, now: now) }
    }

    public func deleteAutomation(id: UUID) -> Bool {
        let initialCount = automations.items.count
        automations.items.removeAll { $0.id == id }
        guard automations.items.count != initialCount else { return false }
        setAutomations(automations.items)
        return true
    }

    private func runThreadFollowUpAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let threadID = automation.threadID,
              let source = root.threads.first(where: { $0.id == threadID })
        else {
            lastError = "The original thread for \(automation.title) is no longer available."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }

        let projectID = knownProjectID(automation.projectID ?? source.projectID)
        let copiedMessages = WorkspaceThreadSeedBuilder.forkSeedMessages(from: source.messages)
        let draft = WorkspaceAutomationRunner.threadFollowUpDraft(
            automation: automation,
            source: source,
            selectedProjectID: projectID,
            copiedMessages: copiedMessages,
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func runWorkspaceScheduleAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let projectID = automation.projectID,
              let project = project(id: projectID)
        else {
            lastError = "The project for \(automation.title) is no longer available."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return nil
        }

        if project.isRemote {
            _ = refreshRemoteProjectContext(projectID)
        } else {
            refreshProjectMetadata(projectID)
        }

        let draft = WorkspaceAutomationRunner.workspaceScheduleDraft(
            automation: automation,
            project: project,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID),
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func applyAutomationRunDraft(_ draft: WorkspaceAutomationRunDraft) -> AutomationRunReport {
        replaceAutomation(draft.automation)
        clearSidebarSelection()
        root.threads.insert(draft.thread, at: 0)
        root.selectedThreadID = draft.thread.id
        root.selectedProjectID = draft.selectedProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(draft.selectedProjectID)
        saveProjects()
        try? threadStore?.save(draft.thread)
        automations.isVisible = true
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return draft.report
    }

    private func replaceAutomation(_ automation: QuillAutomation) {
        guard let index = automations.items.firstIndex(where: { $0.id == automation.id }) else { return }
        automations.items[index] = automation
        setAutomations(automations.items)
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
    public func openBrowserPreview(_ input: String? = nil, workspaceRoot: URL? = nil) -> Bool {
        let rawValue = input ?? browser.addressDraft
        guard let url = WorkspaceBrowserLocationResolver(workspaceRoot: workspaceRoot).resolve(rawValue) else {
            browser.isVisible = true
            browser.status = "Invalid address"
            lastError = "Enter an http, https, file, localhost, or project file URL."
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return false
        }

        WorkspaceBrowserEngine.openPage(url, state: &browser, updateHistory: true)
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func goBackInBrowser() -> Bool {
        guard WorkspaceBrowserEngine.goBack(state: &browser) else { return false }
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func goForwardInBrowser() -> Bool {
        guard WorkspaceBrowserEngine.goForward(state: &browser) else { return false }
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func reloadBrowserPreview() -> Bool {
        guard WorkspaceBrowserEngine.reload(state: &browser) else { return false }
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func openBrowserPreview(
        _ input: String? = nil,
        workspaceRoot: URL? = nil,
        pageFetcher: any BrowserPageFetching
    ) async -> Bool {
        guard openBrowserPreview(input, workspaceRoot: workspaceRoot) else { return false }
        _ = await refreshBrowserSnapshot(pageFetcher: pageFetcher)
        return true
    }

    @discardableResult
    public func refreshBrowserSnapshot(pageFetcher: any BrowserPageFetching) async -> Bool {
        guard let currentURL = browser.currentURL,
              let url = URL(string: currentURL),
              WorkspaceBrowserLocationResolver.canFetchSnapshot(for: url)
        else {
            return false
        }

        browser.status = "Fetching snapshot"
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)

        do {
            let fetchedPage = try await pageFetcher.fetchHTML(from: url)
            guard browser.currentURL == currentURL else { return false }

            WorkspaceBrowserEngine.applyFetchedPage(fetchedPage, originalURL: url, state: &browser)
            lastError = nil
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        } catch {
            guard browser.currentURL == currentURL else { return false }
            WorkspaceBrowserEngine.markSnapshotFetchFailure(error, state: &browser)
            lastError = nil
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return false
        }
    }

    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        WorkspaceBrowserEngine.addComment(text, state: &browser)
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let thread = WorkspaceThreadCreationEngine.newThread(context: WorkspaceThreadCreationContext(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: effectiveProjectID),
            memories: memoryNotes(for: effectiveProjectID)
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
        saveThreads(result.changedThreads)
        for thread in result.removedThreads {
            try? threadStore?.delete(thread.id)
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
        let metadata = WorkspaceProjectMetadata(
            instructions: ProjectInstructionLoader.load(from: standardized),
            localActions: LocalEnvironmentActionLoader.load(from: standardized),
            extensionManifests: ProjectExtensionManifestLoader.load(from: standardized),
            memories: MemoryNoteLoader.loadProject(from: standardized)
        )
        let result = WorkspaceProjectEngine.upsertLocalProject(
            path: standardized,
            name: name,
            metadata: metadata,
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
            let refreshedInstructions = instructions(for: id)
            let refreshedMemories = memoryNotes(for: id)
            mutateSelectedThread { thread in
                guard thread.projectID == id else { return }
                thread.instructions = refreshedInstructions
                thread.memories = refreshedMemories
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
            try? threadStore?.save(thread)
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
        try? threadStore?.save(changedThread)
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
    private func insertCreatedThread(
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
            try? threadStore?.save(thread)
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
        try? threadStore?.save(changedThread)
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
        try? threadStore?.save(result.changedThread)
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
        try? threadStore?.save(result.changedThread)
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
        try? threadStore?.delete(id)
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

    public func setModel(_ model: String) {
        let modelID = WorkspaceConfigurationEngine.setModel(model, config: &root.config)
        mutateSelectedThread { thread in
            WorkspaceConfigurationEngine.setModelID(modelID, thread: &thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
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
        let prompt = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if let command = SlashCommandParser.parse(prompt) {
            composer.draft = ""
            lastError = nil
            handleSlashCommand(command, originalPrompt: prompt, workspaceRoot: workspaceRoot)
            return
        }

        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return }
        syncThreadContext(into: &thread)
        let threadID = thread.id

        composer.draft = ""
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        do {
            try Task.checkCancellation()
            let activeRunner = WorkspaceAgentRunContextBuilder(
                selectedProject: selectedProject,
                browser: browser,
                computerUseBackend: computerUseBackend,
                globalMemoryDirectory: globalMemoryDirectory,
                mcpToolDefinitions: mcpRuntime.toolDefinitions(
                    manifests: selectedProject?.extensionManifests ?? [],
                    extensions: extensions
                ),
                mcpToolExecutionOverride: mcpRuntime.executionOverride(extensions: extensions),
                sshRemoteShellExecutor: sshRemoteShellExecutor
            ).configuredRunner(from: runner)
            let result = try await activeRunner.send(
                prompt,
                in: thread,
                workspaceRoot: workspaceRoot,
                onProgress: { [weak self] progressThread in
                    await self?.applyAgentProgress(progressThread, expectedThreadID: threadID)
                }
            )
            try Task.checkCancellation()
            thread = result.thread
            if WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread) {
                refreshThreadMemoryContext(&thread)
            }
            replaceThread(thread)
            try threadStore?.save(thread)
            composer.isSending = false
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        } catch is CancellationError {
            finishCancelledSend(userPrompt: prompt, threadID: threadID)
        } catch {
            composer.isSending = false
            lastError = String(describing: error)
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
        }
    }

    private func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard thread.id == expectedThreadID else { return }
        replaceThread(thread)
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: WorkspaceAgentStatusBuilder.status(for: thread))
    }

    public func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let actionCall = action.toolCall
        let actionResult = executeReviewGitToolCall(actionCall, router: router)
        appendToolRun(call: actionCall, result: actionResult)

        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult = executeReviewGitToolCall(diffCall, router: router)
        appendToolRun(call: diffCall, result: diffResult)

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        let status = actionResult.ok && diffResult.ok
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
        refreshTopBar(agentStatus: status)
    }

    private func executeReviewGitToolCall(_ call: ToolCall, router: ToolRouter) -> ToolResult {
        guard let project = selectedProject, project.isRemote else {
            return router.execute(call)
        }
        return WorkspaceRemoteProjectToolExecutor.execute(
            call,
            project: project,
            executor: sshRemoteShellExecutor
        )
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
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func runWorkspaceCommand(_ commandID: String, workspaceRoot: URL) -> Bool {
        guard let plan = WorkspaceCommandPlan(commandID: commandID) else { return false }
        switch plan {
        case .localEnvironmentAction(let actionID):
            return runLocalEnvironmentAction(actionID, workspaceRoot: workspaceRoot)
        case .deleteMemory(let id):
            return deleteGlobalMemory(id: id)
        case .updateAutomationStatus(let id, let status):
            return updateAutomationStatus(id: id, status: status)
        case .runAutomation(let id):
            return runAutomation(id: id) != nil
        case .deleteAutomation(let id):
            return deleteAutomation(id: id)
        case .createThreadFollowUpAfter(let seconds):
            return createThreadFollowUpAutomation(after: seconds) != nil
        case .createWorkspaceScheduleAfter(let seconds):
            return createWorkspaceScheduleAutomation(after: seconds) != nil
        case .createThreadFollowUpEvery(let recurrence):
            return createThreadFollowUpAutomation(every: recurrence) != nil
        case .createWorkspaceScheduleEvery(let recurrence):
            return createWorkspaceScheduleAutomation(every: recurrence) != nil
        case .startMCPServer(let id):
            return startMCPServer(id: id, workspaceRoot: workspaceRoot)
        case .stopMCPServer(let id):
            return stopMCPServer(id: id)
        case .updateExtension(let id):
            return runProjectExtensionUpdate(id: id, workspaceRoot: workspaceRoot)
        case .toggleThreadSelection(let id):
            toggleSidebarThreadSelection(id)
            return true
        case .toggleActivitySection(let section):
            toggleActivitySection(section)
            return true
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .runTool(let toolName):
            runToolCall(
                ToolCall(name: toolName, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
            return true
        case .action(let action):
            return runWorkspaceCommandAction(action)
        }
    }

    @discardableResult
    private func runWorkspaceCommandAction(_ action: WorkspaceCommandAction) -> Bool {
        guard let effect = WorkspaceCommandActionPlanner(
            selectedProjectID: root.selectedProjectID,
            selectedProject: selectedProject,
            selectedThreadID: root.selectedThreadID,
            selectedThread: selectedThread
        ).effect(for: action) else {
            return false
        }
        return runWorkspaceCommandActionEffect(effect)
    }

    @discardableResult
    private func runWorkspaceCommandActionEffect(_ effect: WorkspaceCommandActionEffect) -> Bool {
        switch effect {
        case .toggleTerminal:
            toggleTerminal()
            return true
        case .clearTerminal:
            return clearTerminalHistory()
        case .toggleBrowser:
            toggleBrowser()
            return true
        case .browserBack:
            return goBackInBrowser()
        case .browserForward:
            return goForwardInBrowser()
        case .browserReload:
            return reloadBrowserPreview()
        case .toggleExtensions:
            toggleExtensions()
            return true
        case .toggleMemories:
            toggleMemories()
            return true
        case .toggleActivity:
            toggleActivity()
            return true
        case .toggleAutomations:
            toggleAutomations()
            return true
        case .createThreadFollowUp:
            return createThreadFollowUpAutomation() != nil
        case .createWorkspaceSchedule:
            return createWorkspaceScheduleAutomation() != nil
        case .createThreadFollowUpTomorrow:
            return createTomorrowMorningThreadFollowUpAutomation() != nil
        case .createWorkspaceScheduleTomorrow:
            return createTomorrowMorningWorkspaceScheduleAutomation() != nil
        case .newProjectThread(let projectID):
            _ = newChat(projectID: projectID)
            return true
        case .refreshProjectContext(let projectID):
            return refreshProjectContext(projectID)
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .removeProject(let projectID):
            return removeProject(projectID)
        case .duplicateThread(let threadID):
            return duplicateThread(threadID) != nil
        case .archiveThread(let threadID):
            archiveThread(threadID)
            return true
        case .unarchiveThread(let threadID):
            return unarchiveThread(threadID)
        case .deleteThread(let threadID):
            return deleteThread(threadID)
        case .sidebarBulkAction(let kind):
            return performSidebarBulkAction(kind)
        case .retryLastTurn:
            return prepareRetryLastUserTurn()
        case .forkFromLast:
            return forkFromLast() != nil
        case .compactContext:
            return compactContext() != nil
        }
    }

    @discardableResult
    private func startMCPServer(id: String, workspaceRoot: URL) -> Bool {
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
    private func stopMCPServer(id: String) -> Bool {
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
            thread.events.append(.init(kind: .notice, summary: summary))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
    }

    @discardableResult
    private func deleteGlobalMemory(id: String) -> Bool {
        guard let globalMemoryDirectory else { return false }
        do {
            let note = try MemoryNoteLoader.deleteGlobal(id: id, from: globalMemoryDirectory)
            let forgottenSummary = WorkspaceMemoryCommandTranscriptPlanner.memoryForgottenSummary(noteTitle: note.title)
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(WorkspaceMemoryCommandTranscriptPlanner.memoryForgotten(
                userText: "Forget memory: \(note.title)",
                noteTitle: note.title
            ))
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: forgottenSummary,
                    payloadJSON: note.relativePath
                ))
            }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        } catch let error as MemoryNoteDeleteError {
            appendLocalCommandTranscript(WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(
                userText: "Forget memory",
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ))
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        } catch {
            appendLocalCommandTranscript(WorkspaceMemoryCommandTranscriptPlanner.memoryNotDeleted(
                userText: "Forget memory",
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: MemoryNoteDeleteError.deleteFailed)
            ))
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        }
    }

    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = localAction(withID: actionID) else {
            return false
        }
        var arguments: [String: Any] = ["cmd": action.command]
        if let environment = action.environment {
            arguments["environment"] = environment
        }
        if let timeoutSeconds = action.timeoutSeconds {
            arguments["timeoutSeconds"] = timeoutSeconds
        }
        runToolCall(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    @discardableResult
    public func runProjectExtensionUpdate(id: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let manifest = selectedProject?.extensionManifests.first(where: { $0.id == id }),
              let command = manifest.updateCommand,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        var arguments: [String: Any] = ["cmd": command]
        if let timeoutSeconds = manifest.updateTimeoutSeconds {
            arguments["timeoutSeconds"] = timeoutSeconds
        }
        let result = runToolCall(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
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
        var arguments: [String: Any] = ["path": request.path]
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = request.base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            arguments["branch"] = branch
        }
        if !base.isEmpty {
            arguments["base"] = base
        }
        let result = runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openCreatedWorktree(result, request: request)
        }
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

    @discardableResult
    public func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        if selectedThread == nil {
            _ = newChat()
        }
        guard selectedThread != nil else {
            return ToolResult(ok: false, error: "No active thread")
        }
        let contextProjectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectMetadata(contextProjectID)
        let refreshedMemories = memoryNotes(for: contextProjectID)
        let refreshedInstructions = instructions(for: contextProjectID)
        mutateSelectedThread { thread in
            thread.memories = refreshedMemories
            thread.instructions = refreshedInstructions
        }
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let result: ToolResult
        if call.name == ToolDefinition.browserInspect.name {
            result = BrowserInspector.toolResult(from: browser)
        } else if call.name == ToolDefinition.planUpdate.name {
            result = PlanUpdateToolExecutor.execute(call)
        } else if selectedProject?.isRemote == true,
                  let project = selectedProject {
            result = WorkspaceRemoteProjectToolExecutor.execute(
                call,
                project: project,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true {
            result = ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
        } else {
            result = router.execute(call)
        }
        appendToolRun(call: call, result: result)
        let followUpResult = appendReviewDiffAfterPatchIfNeeded(
            call: call,
            result: result,
            router: router
        )

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        let ok = result.ok && (followUpResult?.ok ?? true)
        let status = ok ? TopBarAgentStatusLabel.idle : TopBarAgentStatusLabel.failed
        refreshTopBar(agentStatus: status)
        return result
    }

    public func runTerminalCommand(workspaceRoot: URL) async {
        await runTerminalCommand(terminal.draft, workspaceRoot: workspaceRoot)
    }

    public func runTerminalCommand(_ input: String, workspaceRoot: URL) async {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !terminal.isRunning else { return }
        syncTerminalSessionToSelectedProject()

        let entryID = UUID()
        terminal.draft = ""
        terminal.isVisible = true
        terminal.isRunning = true
        terminal.entries.append(TerminalCommandState(
            id: entryID,
            command: command,
            stdout: "",
            stderr: "",
            exitCode: nil,
            ok: false,
            status: .running
        ))
        lastError = nil
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.terminal)

        guard let executionContext = WorkspaceTerminalEngine.executionContext(
            command: command,
            selectedProject: selectedProject,
            terminalCurrentDirectoryURL: terminalCurrentDirectoryURL,
            terminal: terminal,
            workspaceRoot: workspaceRoot,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        ) else {
            WorkspaceTerminalEngine.finishEntry(
                id: entryID,
                stdout: "",
                stderr: "SSH Remote project is missing a usable host.",
                exitCode: nil,
                ok: false,
                status: .failed,
                terminal: &terminal
            )
            terminal.isRunning = false
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return
        }
        WorkspaceTerminalEngine.updateExecutionContext(
            id: entryID,
            executionContext: executionContext.surface,
            terminal: &terminal
        )

        var finalResult: ToolResult?
        for await event in ShellToolExecutor().runStreaming(executionContext.request) {
            if Task.isCancelled || terminal.entries.first(where: { $0.id == entryID })?.status == .stopped {
                break
            }
            switch event {
            case .stdout(let text):
                WorkspaceTerminalEngine.appendOutput(id: entryID, stdout: text, terminal: &terminal)
            case .stderr(let text):
                WorkspaceTerminalEngine.appendOutput(id: entryID, stderr: text, terminal: &terminal)
            case .finished(let result):
                finalResult = result
            }
        }

        if terminal.entries.first(where: { $0.id == entryID })?.status == .stopped {
            WorkspaceTerminalEngine.removeMarkers(executionContext.markerURLs)
            terminal.isRunning = false
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
            return
        }
        guard !Task.isCancelled, let result = finalResult else {
            WorkspaceTerminalEngine.removeMarkers(executionContext.markerURLs)
            WorkspaceTerminalEngine.finishEntry(
                id: entryID,
                stdout: "",
                stderr: "Command stopped.",
                exitCode: nil,
                ok: false,
                status: .stopped,
                terminal: &terminal
            )
            terminal.isRunning = false
            lastError = nil
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
            return
        }

        let terminalResult = WorkspaceTerminalEngine.sessionResult(for: executionContext, stdout: result.stdout)
        terminal.currentDirectoryPath = terminalResult.currentDirectoryPath
        if let environmentDelta = terminalResult.environmentDelta {
            terminal.environmentOverrides = environmentDelta.overrides
            terminal.removedEnvironmentKeys = environmentDelta.removedKeys
        }
        WorkspaceTerminalEngine.finishEntry(
            id: entryID,
            stdout: terminalResult.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            ok: result.ok,
            status: result.ok ? .done : .failed,
            terminal: &terminal
        )
        terminal.isRunning = false
        let status = result.ok ? TopBarAgentStatusLabel.idle : TopBarAgentStatusLabel.failed
        refreshTopBar(agentStatus: status)
    }

    public func cancelActiveWork() {
        let hadRunningMCPServers = mcpRuntime.cancelAll(extensions: &extensions)
        let hadActiveWork = composer.isSending || terminal.isRunning || hadRunningMCPServers
        composer.isSending = false
        terminal.isRunning = false
        WorkspaceTerminalEngine.stopRunningEntries(terminal: &terminal)
        lastError = nil
        if hadActiveWork {
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
        }
    }

    private func appendToolRun(call: ToolCall, result: ToolResult) {
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        }
    }

    private func openCreatedWorktree(_ result: ToolResult, request: WorkspaceWorktreeCreateRequest) {
        guard let artifact = result.artifacts.first else { return }
        if selectedProject?.isRemote == true {
            openCreatedRemoteWorktree(artifact, request: request)
            return
        }
        let worktreeURL = URL(fileURLWithPath: artifact).standardizedFileURL
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return }

        let projectID = addProject(path: worktreeURL, name: Self.defaultProjectName(for: worktreeURL))
        refreshProjectMetadata(projectID)

        let opened = WorkspaceWorktreeOpenEngine.localThread(
            worktreeURL: worktreeURL,
            context: worktreeOpenContext(projectID: projectID, request: request)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func openCreatedRemoteWorktree(_ artifact: String, request: WorkspaceWorktreeCreateRequest) {
        guard let connection = ProjectConnection.parseSSH(artifact),
              let projectID = addSSHProject(artifact, name: Self.defaultSSHProjectName(for: connection)) else {
            return
        }

        let opened = WorkspaceWorktreeOpenEngine.remoteThread(
            connection: connection,
            context: worktreeOpenContext(projectID: projectID, request: request)
        )
        openCreatedWorktreeThread(opened.thread, projectID: projectID)
    }

    private func worktreeOpenContext(
        projectID: UUID,
        request: WorkspaceWorktreeCreateRequest
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceWorktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID)
        )
    }

    private func openCreatedWorktreeThread(_ thread: ChatThread, projectID: UUID) {
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = projectID
        syncTerminalSessionToSelectedProject()
        touchProject(projectID)
        saveProjects()
        try? threadStore?.save(thread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    private func appendReviewDiffAfterPatchIfNeeded(
        call: ToolCall,
        result: ToolResult,
        router: ToolRouter
    ) -> ToolResult? {
        guard call.name == ToolDefinition.applyPatch.name, result.ok else {
            return nil
        }
        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult: ToolResult
        if let project = selectedProject, project.isRemote {
            diffResult = WorkspaceRemoteProjectToolExecutor.execute(
                diffCall,
                project: project,
                executor: sshRemoteShellExecutor
            )
        } else {
            diffResult = router.execute(diffCall)
        }
        appendToolRun(call: diffCall, result: diffResult)
        return diffResult
    }

    private func toolArgumentsJSON(_ values: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) {
        switch command {
        case .help:
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.help(userText: originalPrompt))
        case .status:
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.status(
                userText: originalPrompt,
                statusText: statusText()
            ))
        case .newChat:
            _ = newChat()
        case .mode(let mode):
            setMode(mode)
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.mode(
                userText: originalPrompt,
                mode: mode
            ))
        case .model(let model):
            setModel(model)
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.model(
                userText: originalPrompt,
                model: model
            ))
        case .renameThread(let title):
            let succeeded = root.selectedThreadID.map { renameThread($0, to: title) } ?? false
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.renameThread(
                userText: originalPrompt,
                requestedTitle: title,
                succeeded: succeeded
            ))
        case .renameProject(let name):
            let succeeded = root.selectedProjectID.map { renameProject($0, to: name) } ?? false
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.renameProject(
                userText: originalPrompt,
                requestedName: name,
                succeeded: succeeded
            ))
        case .sshProject(let address):
            if let projectID = addSSHProject(address),
               let project = root.projects.first(where: { $0.id == projectID }) {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded(
                    userText: originalPrompt,
                    projectName: project.name,
                    displayPath: project.displayPath
                ))
            } else {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.sshProjectFailed(
                    userText: originalPrompt,
                    message: lastError
                ))
            }
        case .remember(let content):
            runRememberSlashCommand(content, originalPrompt: originalPrompt)
        case .threadFollowUp(let scheduleText):
            if let automation = createThreadFollowUpAutomation(matching: scheduleText) {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled(
                    userText: originalPrompt,
                    scheduleDescription: automation.scheduleDescription
                ))
            } else {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.threadFollowUpFailed(
                    userText: originalPrompt,
                    message: lastError
                ))
            }
        case .workspaceSchedule(let scheduleText):
            if let automation = createWorkspaceScheduleAutomation(matching: scheduleText) {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled(
                    userText: originalPrompt,
                    scheduleDescription: automation.scheduleDescription
                ))
            } else {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleFailed(
                    userText: originalPrompt,
                    message: lastError
                ))
            }
        case .workspaceCommand(let commandID):
            if !runWorkspaceCommand(commandID, workspaceRoot: workspaceRoot) {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed(
                    userText: originalPrompt
                ))
            }
        case .toolCall(let call):
            _ = runToolCall(call, workspaceRoot: workspaceRoot)
        case .environmentAction(let query):
            runEnvironmentSlashCommand(query, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
        case .invalid(let message):
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.invalid(
                userText: originalPrompt,
                message: message
            ))
        case .unknown(let name):
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.unknown(
                userText: originalPrompt,
                name: name
            ))
        }
        composer.isSending = false
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    private func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        guard let globalMemoryDirectory else {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.memoryNotSaved(
                userText: originalPrompt,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: MemoryNoteWriteError.unavailable)
            ))
            return
        }

        do {
            let saved = try WorkspaceMemoryRememberToolExecutor.saveGlobal(content: content, to: globalMemoryDirectory)
            let note = saved.note
            let savedSummary = WorkspaceSlashCommandTranscriptPlanner.memorySavedSummary(noteTitle: note.title)
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.memorySaved(
                userText: originalPrompt,
                noteTitle: note.title
            ))
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: savedSummary,
                    payloadJSON: note.relativePath
                ))
            }
        } catch let error as MemoryNoteWriteError {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.memoryNotSaved(
                userText: originalPrompt,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            ))
        } catch {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.memoryNotSaved(
                userText: originalPrompt,
                message: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: MemoryNoteWriteError.writeFailed)
            ))
        }
    }

    private func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.environmentActions(
                userText: originalPrompt,
                actions: selectedProject?.localActions ?? []
            ))
            return
        }

        guard let action = localAction(matching: query) else {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound(
                userText: originalPrompt,
                query: query
            ))
            return
        }
        _ = runLocalEnvironmentAction(action.id, workspaceRoot: workspaceRoot)
    }

    private func appendLocalCommandTranscript(_ transcript: WorkspaceLocalCommandTranscript) {
        appendLocalCommandTranscript(
            userText: transcript.userText,
            assistantText: transcript.assistantText,
            title: transcript.title
        )
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
                thread.title = WorkspaceThreadSeedBuilder.title(fromUserPrompt: userPrompt)
            }
            if !thread.messages.contains(where: { $0.role == .user && $0.content == userPrompt }) {
                thread.messages.append(ChatMessage(role: .user, content: userPrompt))
            }
            let summary = "Stopped by user"
            if let lastEvent = thread.events.last,
               lastEvent.kind == .toolQueued || lastEvent.kind == .toolRunning {
                thread.events.append(.init(
                    kind: .toolFailed,
                    summary: summary,
                    payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
                ))
            }
            if thread.events.last?.kind != .notice || thread.events.last?.summary != summary {
                thread.events.append(.init(kind: .notice, summary: summary))
            }
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.stopped)
    }

    private func statusText() -> String {
        WorkspaceStatusTextBuilder.statusText(for: WorkspaceStatusContext(
            projectName: selectedProject?.name ?? root.topBar.projectName ?? "No project",
            threadTitle: selectedThread?.title ?? "No chat",
            instructions: selectedProject?.instructions ?? selectedThread?.instructions ?? [],
            memories: selectedThread?.memories ?? memoryNotes(for: root.selectedProjectID),
            mode: root.topBar.mode,
            model: root.topBar.model,
            agentStatus: root.topBar.agentStatus
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

    private func saveThreads(_ threads: [ChatThread]) {
        for thread in threads {
            try? threadStore?.save(thread)
        }
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
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
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
        refreshGlobalMemories()
        refreshProjectMetadata(projectID)
        let refreshedInstructions = instructions(for: projectID)
        let refreshedMemories = memoryNotes(for: projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedInstructions
            thread.memories = refreshedMemories
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
        WorkspaceProjectEngine.touchProject(id, projects: &root.projects)
    }

    private func refreshProjectMetadata(_ id: UUID?) {
        refreshGlobalMemories()
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        guard !root.projects[index].isRemote else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        let metadata = WorkspaceProjectMetadata(
            instructions: ProjectInstructionLoader.load(from: rootURL),
            localActions: LocalEnvironmentActionLoader.load(from: rootURL),
            extensionManifests: ProjectExtensionManifestLoader.load(from: rootURL),
            memories: MemoryNoteLoader.loadProject(from: rootURL)
        )
        WorkspaceProjectEngine.applyMetadata(metadata, to: id, projects: &root.projects, includeLocalExtensions: true)
    }

    private func refreshRemoteProjectContext(_ id: UUID) -> Bool {
        refreshGlobalMemories()
        guard let index = root.projects.firstIndex(where: { $0.id == id }),
              root.projects[index].isRemote
        else {
            return false
        }

        do {
            let context = try SSHRemoteProjectContextLoader.load(
                connection: root.projects[index].connection,
                executor: sshRemoteShellExecutor
            )
            let metadata = WorkspaceProjectMetadata(
                instructions: context.instructions,
                localActions: [],
                extensionManifests: [],
                memories: context.memories
            )
            WorkspaceProjectEngine.applyMetadata(metadata, to: id, projects: &root.projects, includeLocalExtensions: false)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func refreshGlobalMemories() {
        guard let globalMemoryDirectory else { return }
        root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
    }

    private func syncThreadContext(into thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        thread.instructions = instructions(for: projectID)
        thread.memories = memoryNotes(for: projectID)
    }

    private func refreshThreadMemoryContext(_ thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        thread.memories = memoryNotes(for: projectID)
    }

    private func instructions(for projectID: UUID?) -> [ProjectInstruction] {
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID })
        else {
            return []
        }
        return project.instructions
    }

    private func memoryNotes(for projectID: UUID?) -> [MemoryNote] {
        let projectMemories: [MemoryNote]
        if let projectID,
           let project = root.projects.first(where: { $0.id == projectID }) {
            projectMemories = project.memories
        } else {
            projectMemories = []
        }
        return root.globalMemories + projectMemories
    }

    private func localAction(withID id: String) -> LocalEnvironmentAction? {
        selectedProject?.localActions.first { $0.id == id }
    }

    private func localAction(matching query: String) -> LocalEnvironmentAction? {
        let normalizedQuery = Self.normalizedActionName(query)
        return selectedProject?.localActions.first { action in
            action.id.caseInsensitiveCompare(query) == .orderedSame
                || action.title.caseInsensitiveCompare(query) == .orderedSame
                || action.relativePath.caseInsensitiveCompare(query) == .orderedSame
                || Self.normalizedActionName(action.title) == normalizedQuery
                || Self.normalizedActionName(action.relativePath) == normalizedQuery
        }
    }

    private static func normalizedActionName(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func knownProjectID(_ id: UUID?) -> UUID? {
        WorkspaceProjectEngine.knownProjectID(id, projects: root.projects)
    }

    private func saveProjects() {
        try? projectStore?.save(root.projects)
    }

    private func saveAutomations() {
        try? automationStore?.save(automations.items)
    }

    private static func defaultProjectName(for url: URL) -> String {
        WorkspaceProjectEngine.defaultProjectName(for: url)
    }

    private static func defaultSSHProjectName(for connection: ProjectConnection) -> String {
        WorkspaceProjectEngine.defaultSSHProjectName(for: connection)
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
