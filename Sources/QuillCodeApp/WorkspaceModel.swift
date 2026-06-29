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
    public internal(set) var memories: MemoriesState
    public internal(set) var activity: ActivityState
    public internal(set) var automations: AutomationsState
    public internal(set) var pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface?
    public internal(set) var sidebarFilter: SidebarSavedFilterKind
    public internal(set) var activeSidebarSavedSearchID: UUID?
    public internal(set) var sidebarSavedSearches: [SidebarSavedSearch]
    public internal(set) var sidebarSelection: SidebarSelectionState
    public private(set) var lastError: String?

    var runner: AgentRunner
    var contextSummaryGenerator: any WorkspaceContextSummaryGenerating
    let threadPersistence: WorkspaceThreadPersistence
    private let projectStore: JSONProjectStore?
    private let automationStore: JSONAutomationStore?
    let globalMemoryDirectory: URL?
    var computerUseBackend: (any ComputerUseBackend)?
    let sshRemoteShellExecutor: SSHRemoteShellExecutor
    let mcpRuntime: WorkspaceMCPRuntime
    var activeTerminalSession: ShellStreamingSession?
    var subagentScheduler = WorkspaceSubagentScheduler()

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        composer: ComposerState = ComposerState(),
        terminal: TerminalState = TerminalState(),
        browser: BrowserState = BrowserState(),
        extensions: ExtensionsState = ExtensionsState(),
        memories: MemoriesState = MemoriesState(),
        activity: ActivityState = ActivityState(),
        automations: AutomationsState = AutomationsState(),
        pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface? = nil,
        sidebarFilter: SidebarSavedFilterKind = .all,
        activeSidebarSavedSearchID: UUID? = nil,
        sidebarSavedSearches: [SidebarSavedSearch] = [],
        sidebarSelection: SidebarSelectionState = SidebarSelectionState(),
        runner: AgentRunner = AgentRunner(),
        contextSummaryGenerator: any WorkspaceContextSummaryGenerating = DeterministicWorkspaceContextSummaryGenerator(),
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
        self.pullRequestReviewDraft = pullRequestReviewDraft
        self.sidebarFilter = sidebarFilter
        self.sidebarSavedSearches = sidebarSavedSearches.filter(\.isValid)
        self.activeSidebarSavedSearchID = self.sidebarSavedSearches.contains { $0.id == activeSidebarSavedSearchID }
            ? activeSidebarSavedSearchID
            : nil
        self.sidebarSelection = sidebarSelection
        self.runner = runner
        self.contextSummaryGenerator = contextSummaryGenerator
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
        activeTerminalSession?.cancel()
        mcpRuntime.terminateAllRunningProcesses()
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

    public func setComputerUseStatus(_ status: ComputerUseStatus) {
        root.topBar.computerUseStatus = status
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setComputerUseBackend(_ backend: any ComputerUseBackend) {
        computerUseBackend = backend
        setComputerUseStatus(backend.status)
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
