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
        refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
            return false
        }

        WorkspaceBrowserEngine.openPage(url, state: &browser, updateHistory: true)
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func goBackInBrowser() -> Bool {
        guard WorkspaceBrowserEngine.goBack(state: &browser) else { return false }
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func goForwardInBrowser() -> Bool {
        guard WorkspaceBrowserEngine.goForward(state: &browser) else { return false }
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func reloadBrowserPreview() -> Bool {
        guard WorkspaceBrowserEngine.reload(state: &browser) else { return false }
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")

        do {
            let fetchedPage = try await pageFetcher.fetchHTML(from: url)
            guard browser.currentURL == currentURL else { return false }

            WorkspaceBrowserEngine.applyFetchedPage(fetchedPage, originalURL: url, state: &browser)
            lastError = nil
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch {
            guard browser.currentURL == currentURL else { return false }
            WorkspaceBrowserEngine.markSnapshotFetchFailure(error, state: &browser)
            lastError = nil
            refreshTopBar(agentStatus: "Idle")
            return false
        }
    }

    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        WorkspaceBrowserEngine.addComment(text, state: &browser)
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        clearSidebarSelection()
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let thread = ChatThread(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: effectiveProjectID),
            memories: memoryNotes(for: effectiveProjectID)
        )
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = effectiveProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(effectiveProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return thread.id
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        clearSidebarSelection()
        let copiedMessages = WorkspaceThreadSeedBuilder.forkSeedMessages(from: source.messages)
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
            instructions: source.instructions,
            memories: source.memories
        )
        root.threads.insert(fork, at: 0)
        root.selectedThreadID = fork.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(fork)
        refreshTopBar(agentStatus: "Idle")
        return fork.id
    }

    @discardableResult
    public func compactContext() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        clearSidebarSelection()
        let copiedMessages = WorkspaceThreadSeedBuilder.compactSeedMessages(from: source)
        let compacted = ChatThread(
            title: "Compact: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Compacted context from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        root.threads.insert(compacted, at: 0)
        root.selectedThreadID = compacted.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(compacted)
        refreshTopBar(agentStatus: "Idle")
        return compacted.id
    }

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
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
        sidebarSelection = plan.nextSelection
        guard let mutation = plan.mutation else {
            return true
        }

        switch mutation {
        case .pin(let ids):
            updateThreads(ids) { thread in
                guard !thread.isArchived else { return }
                thread.isPinned = true
            }
        case .unpin(let ids):
            updateThreads(ids) { thread in
                thread.isPinned = false
            }
        case .archive(let ids):
            var threads = root.threads
            guard let result = WorkspaceThreadLifecycleEngine.archiveThreads(
                ids,
                threads: &threads
            ) else {
                return false
            }
            root.threads = threads
            saveThreads(result.changedThreads)
            applySidebarBulkFollowUpSelection(plan.followUpSelection, removing: ids)
            saveProjects()
        case .unarchive(let ids):
            var threads = root.threads
            guard let result = WorkspaceThreadLifecycleEngine.unarchiveThreads(
                ids,
                threads: &threads
            ) else {
                return false
            }
            root.threads = threads
            saveThreads(result.changedThreads)
            applySidebarBulkFollowUpSelection(plan.followUpSelection, removing: ids)
            saveProjects()
        case .delete(let ids):
            var threads = root.threads
            guard let result = WorkspaceThreadLifecycleEngine.deleteThreads(
                ids,
                threads: &threads
            ) else {
                return false
            }
            root.threads = threads
            for thread in result.removedThreads {
                try? threadStore?.delete(thread.id)
            }
            applySidebarBulkFollowUpSelection(plan.followUpSelection, removing: ids)
            saveProjects()
        }

        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
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
            refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func renameProject(_ id: UUID, to name: String) -> Bool {
        guard WorkspaceProjectEngine.renameProject(id, to: name, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func duplicateThread(_ id: UUID) -> UUID? {
        guard let source = root.threads.first(where: { $0.id == id }) else { return nil }
        clearSidebarSelection()
        let duplicate = WorkspaceThreadLifecycleEngine.duplicateThread(
            source,
            projectID: knownProjectID(source.projectID)
        )
        root.threads.insert(duplicate, at: 0)
        root.selectedThreadID = duplicate.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(duplicate)
        refreshTopBar(agentStatus: "Idle")
        return duplicate.id
    }

    public func togglePinThread(_ id: UUID) {
        var threads = root.threads
        guard let changedThread = WorkspaceThreadLifecycleEngine.togglePinThread(
            id,
            threads: &threads
        ) else { return }
        root.threads = threads
        try? threadStore?.save(changedThread)
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func setMode(_ mode: AgentMode) {
        root.config.mode = mode
        mutateSelectedThread { thread in
            thread.mode = mode
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func setModel(_ model: String) {
        let modelID = TrustedRouterDefaults.normalizedDefaultModelID(model)
        root.config.defaultModel = modelID
        mutateSelectedThread { thread in
            thread.model = modelID
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func toggleModelFavorite(_ model: String) {
        let modelID = TrustedRouterDefaults.canonicalModelID(model)
        guard !modelID.isEmpty else { return }
        if let index = root.config.favoriteModels.firstIndex(of: modelID) {
            root.config.favoriteModels.remove(at: index)
        } else {
            root.config.favoriteModels.append(modelID)
        }
        root.config.favoriteModels = AppConfig(favoriteModels: root.config.favoriteModels).favoriteModels
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setModelCatalog(_ models: [ModelInfo]) {
        guard !models.isEmpty else { return }
        root.modelCatalog = TrustedRouterDefaults.normalizedModelCatalog(models)
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
        refreshTopBar(agentStatus: "Running")

        do {
            try Task.checkCancellation()
            let activeMCPToolDefinitions = mcpToolDefinitionsForReadyServers()
            let activeMCPExecutor = mcpToolExecutionOverride()
            let activePlanDefinitions = [ToolDefinition.planUpdate]
            let activePlanExecutor = planToolExecutionOverride()
            let activeBrowserDefinitions = [ToolDefinition.browserInspect]
            let activeBrowserExecutor = browserToolExecutionOverride(snapshot: browser)
            let activeComputerDefinitions = computerUseBackend == nil ? [] : ToolDefinition.computerUseDefinitions
            let activeComputerExecutor = computerUseToolExecutionOverride()
            let activeMemoryDefinitions = globalMemoryDirectory == nil ? [] : [ToolDefinition.memoryRemember]
            let activeMemoryExecutor = memoryToolExecutionOverride()
            let activeRemoteProjectExecutor = remoteProjectToolExecutionOverride(project: selectedProject)
            var activeRunner = runner
            activeRunner.baseToolDefinitions = baseToolDefinitionsForSelectedProject()
            activeRunner.additionalToolDefinitions = activePlanDefinitions
                + activeBrowserDefinitions
                + activeComputerDefinitions
                + activeMemoryDefinitions
                + activeMCPToolDefinitions
            activeRunner.toolExecutionOverride = WorkspaceToolExecutionOverrideCombiner.combine(
                plan: activePlanExecutor,
                browser: activeBrowserExecutor,
                computerUse: activeComputerExecutor,
                memory: activeMemoryExecutor,
                mcp: activeMCPExecutor,
                remoteProject: activeRemoteProjectExecutor
            )

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
            if Self.didSaveMemory(in: thread) {
                refreshThreadMemoryContext(&thread)
            }
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
        case .notice where thread.events.last?.summary == AgentRunner.streamingNotice:
            return "Streaming"
        case .toolCompleted:
            return "Finishing"
        case .toolFailed:
            return "Failed"
        case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice, .none:
            return "Running"
        }
    }

    public func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }
        lastError = nil
        refreshTopBar(agentStatus: "Running")

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
        refreshTopBar(agentStatus: actionResult.ok && diffResult.ok ? "Idle" : "Failed")
    }

    private func executeReviewGitToolCall(_ call: ToolCall, router: ToolRouter) -> ToolResult {
        guard let project = selectedProject, project.isRemote else {
            return router.execute(call)
        }
        return Self.executeRemoteGitToolCall(
            call,
            connection: project.connection,
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
        refreshTopBar(agentStatus: "Idle")
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
        switch action {
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
        case .projectNewChat:
            guard let projectID = root.selectedProjectID else { return false }
            _ = newChat(projectID: projectID)
            return true
        case .projectRefreshContext:
            guard let projectID = root.selectedProjectID else { return false }
            return refreshProjectContext(projectID)
        case .projectRename:
            guard let name = selectedProject?.name else { return false }
            setDraft("/project rename \(name)")
            return true
        case .projectRemove:
            guard let projectID = root.selectedProjectID else { return false }
            return removeProject(projectID)
        case .threadRename:
            guard let title = selectedThread?.title else { return false }
            setDraft("/rename \(title)")
            return true
        case .threadDuplicate:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return duplicateThread(selectedThreadID) != nil
        case .threadArchive:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            archiveThread(selectedThreadID)
            return true
        case .threadUnarchive:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return unarchiveThread(selectedThreadID)
        case .threadDelete:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return deleteThread(selectedThreadID)
        case .threadSelectionStart:
            return performSidebarBulkAction(.select)
        case .threadSelectionSelectAll:
            return performSidebarBulkAction(.selectAll)
        case .threadSelectionClear:
            return performSidebarBulkAction(.clearSelection)
        case .threadBulkPin:
            return performSidebarBulkAction(.pin)
        case .threadBulkUnpin:
            return performSidebarBulkAction(.unpin)
        case .threadBulkArchive:
            return performSidebarBulkAction(.archive)
        case .threadBulkUnarchive:
            return performSidebarBulkAction(.unarchive)
        case .threadBulkDelete:
            return performSidebarBulkAction(.delete)
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

    private func mcpToolDefinitionsForReadyServers() -> [ToolDefinition] {
        mcpRuntime.toolDefinitions(
            manifests: selectedProject?.extensionManifests ?? [],
            extensions: extensions
        )
    }

    private func mcpToolExecutionOverride() -> AgentToolExecutionOverride? {
        mcpRuntime.executionOverride(extensions: extensions)
    }

    private func computerUseToolExecutionOverride() -> AgentToolExecutionOverride? {
        guard let computerUseBackend else { return nil }
        let executor = ComputerUseToolExecutor(backend: computerUseBackend)
        return { call, _ in
            await executor.execute(call)
        }
    }

    private func browserToolExecutionOverride(snapshot: BrowserState) -> AgentToolExecutionOverride {
        { call, _ in
            guard call.name == ToolDefinition.browserInspect.name else { return nil }
            return BrowserInspector.toolResult(from: snapshot)
        }
    }

    private func planToolExecutionOverride() -> AgentToolExecutionOverride {
        { call, _ in
            guard call.name == ToolDefinition.planUpdate.name else { return nil }
            return PlanUpdateToolExecutor.execute(call)
        }
    }

    private func memoryToolExecutionOverride() -> AgentToolExecutionOverride? {
        guard let directory = globalMemoryDirectory else { return nil }
        return { call, _ in
            guard call.name == ToolDefinition.memoryRemember.name else { return nil }
            return Self.executeMemoryRememberTool(call, directory: directory)
        }
    }

    private func baseToolDefinitionsForSelectedProject() -> [ToolDefinition] {
        selectedProject?.isRemote == true
            ? Self.remoteProjectToolDefinitions
            : ToolRouter.definitions
    }

    private static let remoteProjectToolDefinitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileWrite,
        .applyPatch,
        .gitStatus,
        .gitDiff,
        .gitStage,
        .gitRestore,
        .gitStageHunk,
        .gitRestoreHunk,
        .gitCommit,
        .gitPush,
        .gitPullRequestCreate,
        .gitPullRequestView,
        .gitPullRequestChecks,
        .gitPullRequestDiff,
        .gitPullRequestCheckout,
        .gitPullRequestReviewers,
        .gitPullRequestLabels,
        .gitPullRequestComment,
        .gitPullRequestReview,
        .gitPullRequestMerge,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeRemove
    ]

    private nonisolated static let remoteProjectGitToolNames: Set<String> = [
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitStageHunk.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.gitPush.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestMerge.name,
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeRemove.name
    ]

    private func remoteProjectToolExecutionOverride(project: ProjectRef?) -> AgentToolExecutionOverride? {
        guard let project, project.isRemote else { return nil }
        let connection = project.connection
        let executor = sshRemoteShellExecutor
        return { call, _ in
            switch call.name {
            case ToolDefinition.shellRun.name:
                return Self.executeRemoteShellToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            case ToolDefinition.fileRead.name, ToolDefinition.fileWrite.name:
                return Self.executeRemoteFileToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            case ToolDefinition.applyPatch.name:
                return Self.executeRemotePatchToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            case let name where Self.remoteProjectGitToolNames.contains(name):
                return Self.executeRemoteGitToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            default:
                return nil
            }
        }
    }

    private nonisolated static func executeRemoteGitToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command: String
            var artifacts: [String] = []
            switch call.name {
            case ToolDefinition.gitStatus.name:
                command = "git status --short --branch"
            case ToolDefinition.gitDiff.name:
                command = args.bool("staged") == true ? "git diff --staged" : "git diff"
            case ToolDefinition.gitStage.name:
                let path = try remoteProjectRelativePath(try args.requiredString("path"))
                command = "git add -- \(shellSingleQuoted(path))"
            case ToolDefinition.gitRestore.name:
                let path = try remoteProjectRelativePath(try args.requiredString("path"))
                let stagedFlag = args.bool("staged") == true ? " --staged" : ""
                command = "git restore\(stagedFlag) -- \(shellSingleQuoted(path))"
            case ToolDefinition.gitStageHunk.name:
                command = try remoteGitHunkCommand(
                    path: try args.requiredString("path"),
                    patch: try args.requiredString("patch"),
                    applyArguments: ["--cached", "--whitespace=nowarn"],
                    successMessage: "Hunk staged.\\n"
                )
            case ToolDefinition.gitRestoreHunk.name:
                command = try remoteGitHunkCommand(
                    path: try args.requiredString("path"),
                    patch: try args.requiredString("patch"),
                    applyArguments: ["--reverse", "--whitespace=nowarn"],
                    successMessage: "Hunk restored.\\n"
                )
            case ToolDefinition.gitCommit.name:
                let message = try args.requiredString("message").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else {
                    throw GitToolError.emptyCommitMessage
                }
                command = "git commit -m \(shellSingleQuoted(message))"
            case ToolDefinition.gitPush.name:
                command = try remoteGitPushCommand(
                    remote: args.string("remote"),
                    branch: args.string("branch"),
                    setUpstream: args.bool("setUpstream") ?? false
                )
            case ToolDefinition.gitPullRequestCreate.name:
                command = try remoteGitPullRequestCommand(
                    title: args.string("title"),
                    body: args.string("body"),
                    base: args.string("base"),
                    head: args.string("head"),
                    draft: args.bool("draft") ?? false,
                    fill: args.bool("fill") ?? false
                )
            case ToolDefinition.gitPullRequestView.name:
                command = try remoteGitPullRequestViewCommand(selector: args.string("selector"))
            case ToolDefinition.gitPullRequestChecks.name:
                command = try remoteGitPullRequestChecksCommand(selector: args.string("selector"))
            case ToolDefinition.gitPullRequestDiff.name:
                command = try remoteGitPullRequestDiffCommand(selector: args.string("selector"))
            case ToolDefinition.gitPullRequestCheckout.name:
                command = try remoteGitPullRequestCheckoutCommand(
                    selector: args.string("selector"),
                    branch: args.string("branch")
                )
            case ToolDefinition.gitPullRequestReviewers.name:
                command = try remoteGitPullRequestReviewersCommand(
                    selector: args.string("selector"),
                    add: args.stringArray("add"),
                    remove: args.stringArray("remove")
                )
            case ToolDefinition.gitPullRequestLabels.name:
                command = try remoteGitPullRequestLabelsCommand(
                    selector: args.string("selector"),
                    add: args.stringArray("add"),
                    remove: args.stringArray("remove")
                )
            case ToolDefinition.gitPullRequestComment.name:
                command = try remoteGitPullRequestCommentCommand(
                    selector: args.string("selector"),
                    body: try args.requiredString("body")
                )
            case ToolDefinition.gitPullRequestReview.name:
                command = try remoteGitPullRequestReviewCommand(
                    selector: args.string("selector"),
                    action: try args.requiredString("action"),
                    body: args.string("body")
                )
            case ToolDefinition.gitPullRequestMerge.name:
                command = try remoteGitPullRequestMergeCommand(
                    selector: args.string("selector"),
                    method: args.string("method"),
                    auto: args.bool("auto") ?? false,
                    deleteBranch: args.bool("deleteBranch") ?? false
                )
            case ToolDefinition.gitWorktreeList.name:
                command = "git worktree list --porcelain"
            case ToolDefinition.gitWorktreeCreate.name:
                let worktreePath = try remoteGitWorktreePath(
                    try args.requiredString("path"),
                    connection: connection
                )
                command = remoteGitWorktreeCreateCommand(
                    worktreePath: worktreePath,
                    branch: args.string("branch"),
                    base: args.string("base")
                )
                artifacts = [remoteArtifactPath(connection: connection, absolutePath: worktreePath)]
            case ToolDefinition.gitWorktreeRemove.name:
                let worktreePath = try remoteGitWorktreePath(
                    try args.requiredString("path"),
                    connection: connection
                )
                command = remoteGitWorktreeRemoveCommand(
                    worktreePath: worktreePath,
                    force: args.bool("force") ?? false
                )
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if [
                ToolDefinition.gitPullRequestCreate.name,
                ToolDefinition.gitPullRequestView.name,
                ToolDefinition.gitPullRequestDiff.name,
                ToolDefinition.gitPullRequestCheckout.name,
                ToolDefinition.gitPullRequestReviewers.name,
                ToolDefinition.gitPullRequestLabels.name,
                ToolDefinition.gitPullRequestComment.name,
                ToolDefinition.gitPullRequestReview.name,
                ToolDefinition.gitPullRequestMerge.name
            ].contains(call.name), result.ok {
                result.artifacts = GitToolExecutor.extractURLs(from: result.stdout)
            } else if result.ok, !artifacts.isEmpty {
                result.artifacts = artifacts
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func remoteGitPushCommand(
        remote: String?,
        branch: String?,
        setUpstream: Bool
    ) throws -> String {
        let remoteName = try GitToolExecutor.safeGitName(
            GitToolExecutor.trimmedNonEmpty(remote) ?? "origin"
        )
        let upstreamArguments = setUpstream ? "-u " : ""
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            let branchName = try GitToolExecutor.safeGitName(branch)
            return "git push \(upstreamArguments)\(shellSingleQuoted(remoteName)) \(shellSingleQuoted(branchName))"
        }

        let invalidBranchMessage = shellSingleQuoted(String(describing: GitToolError.invalidGitName("$branch")))
        return [
            "branch=$(git branch --show-current)",
            "test -n \"$branch\" || { printf '%s\\n' \(shellSingleQuoted(String(describing: GitToolError.noCurrentBranch))) >&2; exit 1; }",
            "case \"$branch\" in -*|*..*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*) printf '%s\\n' \(invalidBranchMessage) >&2; exit 1;; esac",
            "git push \(upstreamArguments)\(shellSingleQuoted(remoteName)) \"$branch\""
        ].joined(separator: " && ")
    }

    private nonisolated static func remoteGitPullRequestCommand(
        title: String?,
        body: String?,
        base: String?,
        head: String?,
        draft: Bool,
        fill: Bool
    ) throws -> String {
        let trimmedTitle = GitToolExecutor.trimmedNonEmpty(title)
        guard fill || trimmedTitle != nil else {
            throw GitToolError.emptyPullRequestTitle
        }

        var arguments = ["gh", "pr", "create"]
        if let trimmedTitle {
            arguments += ["--title", trimmedTitle]
        }
        if let body = GitToolExecutor.trimmedNonEmpty(body) {
            arguments += ["--body", body]
        }
        if let base = GitToolExecutor.trimmedNonEmpty(base) {
            arguments += ["--base", try GitToolExecutor.safeGitName(base)]
        }
        if let head = GitToolExecutor.trimmedNonEmpty(head) {
            arguments += ["--head", try GitToolExecutor.safeGitName(head)]
        }
        if draft {
            arguments.append("--draft")
        }
        if fill {
            arguments.append("--fill")
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestViewCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append("--comments")
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestChecksCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "checks"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestDiffCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "diff"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestCheckoutCommand(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitToolExecutor.safeGitName(branch)]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestReviewersCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let reviewersToAdd = try GitToolExecutor.safePullRequestReviewers(add)
        let reviewersToRemove = try GitToolExecutor.safePullRequestReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if !reviewersToAdd.isEmpty {
            arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
        }
        if !reviewersToRemove.isEmpty {
            arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestLabelsCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let labelsToAdd = try GitToolExecutor.safePullRequestLabels(add)
        let labelsToRemove = try GitToolExecutor.safePullRequestLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if !labelsToAdd.isEmpty {
            arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
        }
        if !labelsToRemove.isEmpty {
            arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestCommentCommand(
        selector: String?,
        body: String
    ) throws -> String {
        guard let body = GitToolExecutor.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["gh", "pr", "comment"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--body", body]
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestReviewCommand(
        selector: String?,
        action: String,
        body: String?
    ) throws -> String {
        let flag = try GitToolExecutor.safePullRequestReviewFlag(action)
        let body = GitToolExecutor.trimmedNonEmpty(body)
        guard flag == "--approve" || body != nil else {
            throw GitToolError.emptyPullRequestReviewBody
        }

        var arguments = ["gh", "pr", "review"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(flag)
        if let body {
            arguments += ["--body", body]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestMergeCommand(
        selector: String?,
        method: String?,
        auto: Bool,
        deleteBranch: Bool
    ) throws -> String {
        var arguments = ["gh", "pr", "merge"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(try GitToolExecutor.safePullRequestMergeFlag(method))
        if auto {
            arguments.append("--auto")
        }
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitWorktreeCreateCommand(
        worktreePath: String,
        branch: String?,
        base: String?
    ) -> String {
        var arguments = ["git", "worktree", "add"]
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            arguments += ["-b", branch]
        }
        arguments.append(worktreePath)
        if let base = GitToolExecutor.trimmedNonEmpty(base) {
            arguments.append(base)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitWorktreeRemoveCommand(
        worktreePath: String,
        force: Bool
    ) -> String {
        let forceFlag = force ? " --force" : ""
        return [
            "worktree=\(shellSingleQuoted(worktreePath))",
            "git worktree list --porcelain | grep -F -x -- \"worktree $worktree\" >/dev/null || { printf 'Git worktree is not registered: %s\\n' \"$worktree\" >&2; exit 1; }",
            "git worktree remove\(forceFlag) -- \"$worktree\""
        ].joined(separator: " && ")
    }

    private nonisolated static func remoteGitWorktreePath(
        _ rawPath: String,
        connection: ProjectConnection
    ) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw GitToolError.emptyPath
        }
        guard let workspace = normalizedAbsolutePOSIXPath(connection.path) else {
            throw GitToolError.outsideWorkspace(connection.path)
        }
        let parent = posixParentPath(workspace)
        let candidateRaw = trimmed.hasPrefix("/") ? trimmed : "\(parent)/\(trimmed)"
        guard let candidate = normalizedAbsolutePOSIXPath(candidateRaw),
              isPOSIXPath(candidate, inside: parent) else {
            throw GitToolError.outsideWorkspace(rawPath)
        }
        guard candidate != workspace else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return candidate
    }

    private nonisolated static func normalizedAbsolutePOSIXPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return nil
        }
        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components.isEmpty ? "/" : "/\(components.joined(separator: "/"))"
    }

    private nonisolated static func posixParentPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return "/" }
        return "/\(components.dropLast().joined(separator: "/"))"
    }

    private nonisolated static func isPOSIXPath(_ path: String, inside parent: String) -> Bool {
        if parent == "/" {
            return path.hasPrefix("/")
        }
        return path == parent || path.hasPrefix("\(parent)/")
    }

    private nonisolated static func remoteGitHunkCommand(
        path: String,
        patch: String,
        applyArguments: [String],
        successMessage: String
    ) throws -> String {
        let relativePath = try remoteProjectRelativePath(path)
        var normalizedPatch = patch
        let trimmedPatch = normalizedPatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPatch.isEmpty else {
            throw GitToolError.emptyPatch
        }
        if let mismatch = GitToolExecutor.mismatchedPatchPath(
            in: normalizedPatch,
            expectedPath: relativePath
        ) {
            throw GitToolError.patchPathMismatch(mismatch)
        }
        if !normalizedPatch.hasSuffix("\n") {
            normalizedPatch.append("\n")
        }

        let encoded = Data(normalizedPatch.utf8).base64EncodedString()
        let flags = applyArguments.map(shellSingleQuoted).joined(separator: " ")
        return [
            "patch_file=\"${TMPDIR:-/tmp}/quillcode-hunk.$$.patch\"",
            "trap 'rm -f \"$patch_file\"' EXIT",
            "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
            "git apply \(flags) --check \"$patch_file\"",
            "git apply \(flags) \"$patch_file\"",
            "printf \(shellSingleQuoted(successMessage))"
        ].joined(separator: " && ")
    }

    private nonisolated static func executeRemoteFileToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let relativePath = try remoteProjectRelativePath(try args.requiredString("path"))
            let command: String
            switch call.name {
            case ToolDefinition.fileRead.name:
                command = "cat -- \(shellSingleQuoted(relativePath))"
            case ToolDefinition.fileWrite.name:
                let content = try args.requiredString("content")
                let encoded = Data(content.utf8).base64EncodedString()
                let directory = remoteDirectory(for: relativePath)
                command = [
                    "mkdir -p -- \(shellSingleQuoted(directory))",
                    "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \(shellSingleQuoted(relativePath))",
                    "printf 'Wrote %s\\n' \(shellSingleQuoted(relativePath))"
                ].joined(separator: " && ")
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if result.ok {
                result.artifacts = [remoteArtifactPath(connection: connection, relativePath: relativePath)]
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func executeRemotePatchToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            var patch = try args.requiredString("patch")
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                return ToolResult(ok: false, error: String(describing: PatchToolError.emptyPatch))
            }
            if let unsafePath = PatchToolExecutor.unsafePath(in: patch) {
                return ToolResult(
                    ok: false,
                    error: String(describing: PatchToolError.unsafePath(unsafePath))
                )
            }
            if !patch.hasSuffix("\n") {
                patch.append("\n")
            }

            let encoded = Data(patch.utf8).base64EncodedString()
            let command = [
                "patch_file=\"${TMPDIR:-/tmp}/quillcode.$$.patch\"",
                "trap 'rm -f \"$patch_file\"' EXIT",
                "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
                "git apply --check \"$patch_file\"",
                "git apply \"$patch_file\"",
                "printf 'Patch applied.\\n'"
            ].joined(separator: " && ")

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func executeRemoteShellToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command = try args.requiredString("cmd")
            let requestConnection = remoteShellConnection(
                connection,
                cwd: args.string("cwd")
            )
            guard let request = executor.request(command: command, connection: requestConnection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func remoteProjectRelativePath(_ rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw FileToolError.outsideWorkspace(rawPath)
        }

        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                throw FileToolError.outsideWorkspace(rawPath)
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else {
            throw FileToolError.outsideWorkspace(rawPath)
        }
        return components.joined(separator: "/")
    }

    private nonisolated static func remoteDirectory(for relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? "." : directory
    }

    private nonisolated static func remoteArtifactPath(
        connection: ProjectConnection,
        relativePath: String
    ) -> String {
        var copy = connection
        copy.path = remotePath(connection.path, appending: relativePath)
        return copy.displayLabel
    }

    private nonisolated static func remoteArtifactPath(
        connection: ProjectConnection,
        absolutePath: String
    ) -> String {
        var copy = connection
        copy.path = absolutePath
        return copy.displayLabel
    }

    private nonisolated static func remoteShellConnection(
        _ connection: ProjectConnection,
        cwd: String?
    ) -> ProjectConnection {
        let trimmedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCWD.isEmpty else { return connection }
        var copy = connection
        if trimmedCWD.hasPrefix("/") || trimmedCWD.hasPrefix("~") {
            copy.path = trimmedCWD
        } else {
            copy.path = remotePath(connection.path, appending: trimmedCWD)
        }
        return copy
    }

    private nonisolated static func remotePath(_ base: String, appending relativePath: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRelative.isEmpty else { return trimmedBase.isEmpty ? "~" : trimmedBase }

        let isAbsolute = trimmedBase.hasPrefix("/")
        let isHome = trimmedBase == "~" || trimmedBase.hasPrefix("~/")
        let baseRemainder: String
        if isAbsolute {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if isHome {
            baseRemainder = String(trimmedBase.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var components: [String] = []
        for component in ([baseRemainder, trimmedRelative].filter { !$0.isEmpty }.joined(separator: "/")).split(separator: "/") {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                } else if !isAbsolute && !isHome {
                    components.append(String(component))
                }
            default:
                components.append(String(component))
            }
        }

        let suffix = components.joined(separator: "/")
        if isAbsolute {
            return "/" + suffix
        }
        if isHome || trimmedBase.isEmpty {
            return suffix.isEmpty ? "~" : "~/" + suffix
        }
        return suffix.isEmpty ? "." : suffix
    }

    private nonisolated static func executeMemoryRememberTool(_ call: ToolCall, directory: URL) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let content = try args.requiredString("content")
            let saved = try saveGlobalMemory(content: content, to: directory)
            return ToolResult(
                ok: true,
                stdout: try JSONHelpers.encodePretty(saved.output),
                artifacts: [saved.note.relativePath]
            )
        } catch {
            return ToolResult(
                ok: false,
                error: userFacingMemoryError(error)
            )
        }
    }

    private nonisolated static func saveGlobalMemory(
        content: String,
        to directory: URL
    ) throws -> (note: MemoryNote, output: MemoryRememberToolOutput) {
        let note = try MemoryNoteLoader.saveGlobal(content: content, to: directory)
        let output = MemoryRememberToolOutput(
            title: note.title,
            relativePath: note.relativePath,
            content: note.content
        )
        return (note, output)
    }

    private nonisolated static func userFacingMemoryError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }

    private nonisolated static func didSaveMemory(in thread: ChatThread) -> Bool {
        thread.events.contains { event in
            guard event.kind == .toolCompleted,
                  event.summary == "\(ToolDefinition.memoryRemember.name) completed",
                  let result = decode(ToolResult.self, event.payloadJSON),
                  result.ok
            else {
                return false
            }
            return result.artifacts.contains { $0.hasPrefix("memories/") }
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
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(
                userText: "Forget memory: \(note.title)",
                assistantText: "Forgot memory: \(note.title). It will no longer be included as background context.",
                title: "Forgot memory: \(note.title)"
            )
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Forgot memory: \(note.title)",
                    payloadJSON: note.relativePath
                ))
            }
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch let error as MemoryNoteDeleteError {
            appendLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: error.localizedDescription,
                title: "Memory not deleted"
            )
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch {
            appendLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: MemoryNoteDeleteError.deleteFailed.localizedDescription,
                title: "Memory not deleted"
            )
            refreshTopBar(agentStatus: "Idle")
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
        refreshTopBar(agentStatus: "Running")

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let result: ToolResult
        if call.name == ToolDefinition.browserInspect.name {
            result = BrowserInspector.toolResult(from: browser)
        } else if call.name == ToolDefinition.planUpdate.name {
            result = PlanUpdateToolExecutor.execute(call)
        } else if selectedProject?.isRemote == true,
                  call.name == ToolDefinition.shellRun.name,
                  let project = selectedProject {
            result = Self.executeRemoteShellToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true,
                  (call.name == ToolDefinition.fileRead.name || call.name == ToolDefinition.fileWrite.name),
                  let project = selectedProject {
            result = Self.executeRemoteFileToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true,
                  call.name == ToolDefinition.applyPatch.name,
                  let project = selectedProject {
            result = Self.executeRemotePatchToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true,
                  Self.remoteProjectGitToolNames.contains(call.name),
                  let project = selectedProject {
            result = Self.executeRemoteGitToolCall(
                call,
                connection: project.connection,
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
        refreshTopBar(agentStatus: ok ? "Idle" : "Failed")
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
        refreshTopBar(agentStatus: "Terminal")

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
            refreshTopBar(agentStatus: "Failed")
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
            refreshTopBar(agentStatus: "Stopped")
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
            refreshTopBar(agentStatus: "Stopped")
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
        refreshTopBar(agentStatus: result.ok ? "Idle" : "Failed")
    }

    private nonisolated static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalEngine.shellSingleQuoted(value)
    }

    public func cancelActiveWork() {
        let hadRunningMCPServers = mcpRuntime.cancelAll(extensions: &extensions)
        let hadActiveWork = composer.isSending || terminal.isRunning || hadRunningMCPServers
        composer.isSending = false
        terminal.isRunning = false
        WorkspaceTerminalEngine.stopRunningEntries(terminal: &terminal)
        lastError = nil
        if hadActiveWork {
            refreshTopBar(agentStatus: "Stopped")
        }
    }

    private func appendToolRun(call: ToolCall, result: ToolResult) {
        let transcriptCall = call.redactedForTranscript()
        let callJSON = (try? JSONHelpers.encodePretty(transcriptCall)) ?? transcriptCall.argumentsJSON
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

        let titleLabel = Self.worktreeThreadLabel(request: request, url: worktreeURL)
        let messageText = "Opened worktree `\(worktreeURL.lastPathComponent)` at `\(worktreeURL.path)`."
        let message = ChatMessage(role: .assistant, content: messageText)
        let thread = ChatThread(
            title: "Worktree: \(titleLabel)",
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            messages: [message],
            events: [
                .init(
                    kind: .notice,
                    summary: "Opened worktree \(worktreeURL.lastPathComponent)",
                    payloadJSON: worktreeURL.path
                ),
                .init(kind: .message, summary: messageText)
            ],
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID)
        )

        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = projectID
        syncTerminalSessionToSelectedProject()
        touchProject(projectID)
        saveProjects()
        try? threadStore?.save(thread)
        refreshTopBar(agentStatus: "Idle")
    }

    private func openCreatedRemoteWorktree(_ artifact: String, request: WorkspaceWorktreeCreateRequest) {
        guard let connection = ProjectConnection.parseSSH(artifact),
              let projectID = addSSHProject(artifact, name: Self.defaultSSHProjectName(for: connection)) else {
            return
        }

        let titleLabel = Self.worktreeThreadLabel(request: request, path: connection.path)
        let pathName = URL(fileURLWithPath: connection.path).lastPathComponent
        let displayName = pathName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? connection.displayLabel
            : pathName
        let messageText = "Opened remote worktree `\(displayName)` at `\(connection.displayLabel)`."
        let message = ChatMessage(role: .assistant, content: messageText)
        let thread = ChatThread(
            title: "Worktree: \(titleLabel)",
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            messages: [message],
            events: [
                .init(
                    kind: .notice,
                    summary: "Opened remote worktree \(displayName)",
                    payloadJSON: connection.displayLabel
                ),
                .init(kind: .message, summary: messageText)
            ],
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID)
        )

        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = projectID
        syncTerminalSessionToSelectedProject()
        touchProject(projectID)
        saveProjects()
        try? threadStore?.save(thread)
        refreshTopBar(agentStatus: "Idle")
    }

    private static func worktreeThreadLabel(request: WorkspaceWorktreeCreateRequest, url: URL) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        return defaultProjectName(for: url)
    }

    private static func worktreeThreadLabel(request: WorkspaceWorktreeCreateRequest, path: String) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? path : lastPathComponent
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
            diffResult = Self.executeRemoteGitToolCall(
                diffCall,
                connection: project.connection,
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
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: SlashCommandCatalog.helpText(),
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
        case .renameThread(let title):
            if let id = root.selectedThreadID, renameThread(id, to: title) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Renamed chat to \(title.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    title: "Rename chat"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not rename this chat. Try /rename New chat title.",
                    title: "Rename chat"
                )
            }
        case .renameProject(let name):
            if let id = root.selectedProjectID, renameProject(id, to: name) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Renamed project to \(name.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    title: "Rename project"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not rename this project. Try /project rename New project name.",
                    title: "Rename project"
                )
            }
        case .sshProject(let address):
            if let projectID = addSSHProject(address),
               let project = root.projects.first(where: { $0.id == projectID }) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Added SSH Remote \(project.name) at \(project.displayPath). Shell, file read/write, apply patch, git status/diff/stage/restore/commit/push/PR checkout/reviewers/labels/merge/worktree, and project context refresh run through SSH.",
                    title: "Add SSH Remote"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: lastError ?? "Use SSH format user@host:/path or ssh://user@host/path.",
                    title: "Add SSH Remote"
                )
            }
        case .remember(let content):
            runRememberSlashCommand(content, originalPrompt: originalPrompt)
        case .threadFollowUp(let scheduleText):
            if let automation = createThreadFollowUpAutomation(matching: scheduleText) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Scheduled a thread follow-up for \(automation.scheduleDescription).",
                    title: "Schedule follow-up"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: lastError ?? "Could not schedule this follow-up.",
                    title: "Schedule follow-up"
                )
            }
        case .workspaceSchedule(let scheduleText):
            if let automation = createWorkspaceScheduleAutomation(matching: scheduleText) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Scheduled a workspace check for \(automation.scheduleDescription).",
                    title: "Schedule workspace check"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: lastError ?? "Could not schedule this workspace check.",
                    title: "Schedule workspace check"
                )
            }
        case .workspaceCommand(let commandID):
            if !runWorkspaceCommand(commandID, workspaceRoot: workspaceRoot) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not run /\(originalPrompt.dropFirst()). Try /help.",
                    title: "Slash command"
                )
            }
        case .toolCall(let call):
            _ = runToolCall(call, workspaceRoot: workspaceRoot)
        case .environmentAction(let query):
            runEnvironmentSlashCommand(query, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
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

    private func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        guard let globalMemoryDirectory else {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: MemoryNoteWriteError.unavailable.localizedDescription,
                title: "Memory not saved"
            )
            return
        }

        do {
            let saved = try Self.saveGlobalMemory(content: content, to: globalMemoryDirectory)
            let note = saved.note
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Saved memory: \(note.title). It will be included as background context in future turns.",
                title: "Memory: \(note.title)"
            )
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Saved memory: \(note.title)",
                    payloadJSON: note.relativePath
                ))
            }
        } catch let error as MemoryNoteWriteError {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: error.localizedDescription,
                title: "Memory not saved"
            )
        } catch {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: MemoryNoteWriteError.writeFailed.localizedDescription,
                title: "Memory not saved"
            )
        }
    }

    private func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let actions = selectedProject?.localActions ?? []
            let message: String
            if actions.isEmpty {
                message = "No local environment actions found. Add scripts under `.quillcode/actions` or `.quillcode/local-env`."
            } else {
                let rows = actions
                    .map { action in
                        let detail = action.detail.map { " — \($0)" } ?? ""
                        let cwd = action.workingDirectory.map { " — cwd: \($0)" } ?? ""
                        let timeout = action.timeoutSeconds.map { " — timeout: \($0)s" } ?? ""
                        return "- `/env \(action.title)` — \(action.relativePath)\(cwd)\(timeout)\(detail)"
                    }
                    .joined(separator: "\n")
                message = "Local environment actions:\n\(rows)"
            }
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: message,
                title: "Local environment actions"
            )
            return
        }

        guard let action = localAction(matching: query) else {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "No local environment action matches `\(query)`. Run `/env` to see available actions.",
                title: "Local environment actions"
            )
            return
        }
        _ = runLocalEnvironmentAction(action.id, workspaceRoot: workspaceRoot)
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
        refreshTopBar(agentStatus: "Stopped")
    }

    private func statusText() -> String {
        let project = selectedProject?.name ?? root.topBar.projectName ?? "No project"
        let thread = selectedThread?.title ?? "No chat"
        let instructionLabel = Self.instructionStatusLabel(for: selectedProject?.instructions ?? selectedThread?.instructions ?? [])
        let memoryLabel = Self.memoryStatusLabel(for: selectedThread?.memories ?? memoryNotes(for: root.selectedProjectID))
        return """
        Project: \(project)
        Thread: \(thread)
        Instructions: \(instructionLabel)
        Memories: \(memoryLabel)
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

    func selectedSidebarThreadIDs() -> [UUID] {
        let resolution = WorkspaceSidebarSelectionEngine.resolve(
            state: sidebarSelection,
            orderedSidebarThreadIDs: root.allSidebarItems.map(\.id),
            validThreadIDs: validThreadIDs()
        )
        sidebarSelection = resolution.state
        return resolution.selectedThreadIDs
    }

    private func applySidebarBulkFollowUpSelection(
        _ followUpSelection: WorkspaceSidebarBulkActionPlanner.FollowUpSelection,
        removing ids: [UUID]
    ) {
        switch followUpSelection {
        case .unchanged:
            return
        case .selectBestAfterRemoving(let preferredProjectID):
            selectBestThread(afterRemoving: ids, preferredProjectID: preferredProjectID)
        case .select(let context):
            root.selectedThreadID = context.id
            root.selectedProjectID = knownProjectID(context.projectID)
            syncTerminalSessionToSelectedProject()
            touchProject(root.selectedProjectID)
        case .reconcileCurrent:
            if let selectedThread {
                root.selectedProjectID = knownProjectID(selectedThread.projectID)
            } else {
                root.selectedProjectID = knownProjectID(root.selectedProjectID)
            }
        }
    }

    private func validThreadIDs() -> Set<UUID> {
        Set(root.threads.map(\.id))
    }

    private func updateThreads(_ ids: [UUID], _ update: (inout ChatThread) -> Void) {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return }
        for index in root.threads.indices where targetIDs.contains(root.threads[index].id) {
            update(&root.threads[index])
            root.threads[index].updatedAt = Date()
            try? threadStore?.save(root.threads[index])
        }
        saveProjects()
    }

    private func saveThreads(_ threads: [ChatThread]) {
        for thread in threads {
            try? threadStore?.save(thread)
        }
    }

    private func selectBestThread(afterRemoving ids: [UUID], preferredProjectID: UUID?) {
        let selection = WorkspaceProjectEngine.selectionAfterRemovingThreads(
            ids,
            preferredProjectID: preferredProjectID,
            projects: root.projects,
            threads: root.threads
        )
        root.selectedThreadID = selection.threadID
        root.selectedProjectID = selection.projectID
        syncTerminalSessionToSelectedProject()
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

    static func instructionStatusLabel(for instructions: [ProjectInstruction]) -> String {
        guard !instructions.isEmpty else { return "No project instructions" }
        let truncated = instructions.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(instructions.count) instruction file\(instructions.count == 1 ? "" : "s") loaded\(truncated)"
    }

    static func memoryStatusLabel(for memories: [MemoryNote]) -> String {
        guard !memories.isEmpty else { return "No memories" }
        let truncated = memories.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(memories.count) memor\(memories.count == 1 ? "y" : "ies")\(truncated)"
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

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
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
