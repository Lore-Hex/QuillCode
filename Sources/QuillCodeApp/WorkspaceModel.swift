import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

@MainActor
public final class QuillCodeWorkspaceModel {
    public internal(set) var root: QuillCodeRootState
    public internal(set) var chrome: WorkspaceChromeState
    public internal(set) var navigationHistory: WorkspaceNavigationHistoryState
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

    /// Set by the desktop layer to post a "come back and look" OS notification when an agent run
    /// finishes while the user is away — finished, errored, or blocked on an approval gate. The whole
    /// point of daily-driving on a loop is not watching, so the app pings you when it needs you. nil in
    /// tests / the CLI, where there is no desktop notification surface.
    public var onRunNotification: (@MainActor @Sendable (AgentRunNotification) -> Void)?
    /// Optional platform hook for browser tools that need a live native browser surface. Desktop installs
    /// this for visible WebKit sessions; nil keeps the pure app-core snapshot executor behavior.
    public var visibleBrowserToolOverride: AgentToolExecutionOverride?

    var runner: AgentRunner
    var contextSummaryGenerator: any WorkspaceContextSummaryGenerating
    /// The active runtime's retry channel; the model drains it into "Self-healing" thread notices while
    /// a run is in flight. nil for the mock runtime (which never retries).
    var retryEventChannel: RetryEventChannel?
    /// Test seam for the verification green-gate: overrides how a verify command is run so a unit test
    /// can supply a fake `ToolResult` instead of spawning a real shell. nil = run the real command.
    var verificationRunner: (@Sendable (LocalEnvironmentAction, URL) async -> ToolResult)?
    let threadPersistence: WorkspaceThreadPersistence
    private let projectStore: JSONProjectStore?
    private let automationStore: JSONAutomationStore?
    private let sidebarSavedSearchStore: JSONSidebarSavedSearchStore?
    /// Persisted per-project permission rules ("always allow/deny"). The agent's safety gate reads
    /// this same store per review, so a rule saved here applies to the very next tool call. Nil
    /// (tests/CLI without persistence) disables saving; approval flows still work as before.
    let permissionRuleStore: PermissionRuleFileStore?
    let globalMemoryDirectory: URL?
    var computerUseBackend: (any ComputerUseBackend)?
    let sshRemoteShellExecutor: SSHRemoteShellExecutor
    let mcpRuntime: WorkspaceMCPRuntime
    var activeTerminalSession: (any ShellInteractiveSession)?
    var subagentScheduler = WorkspaceSubagentScheduler()
    /// The edit session for app/UI-initiated tool runs (`runToolCall`): review-pane opens,
    /// slash commands, diagnostic applies. Deliberately SEPARATE from every chat thread's
    /// `FileEditSessionGuard.session(for:)`, so a file the user merely opened in the UI never
    /// becomes writable to a model thread that has not read it.
    let uiEditSessionGuard = FileEditSessionGuard()
    /// Bounded, cached index of the selected local project's files, used to power
    /// composer `@` file mentions. Empty for remote or unselected projects.
    public internal(set) var fileMentionIndex = WorkspaceFileIndex()
    /// Workspace-relative paths with uncommitted changes, captured from the most recent
    /// successful `git status` run (the same stdout the branch chip parses — no extra git
    /// invocation). Used to boost/badge changed files in `@` mentions.
    public internal(set) var changedFilePaths: Set<String> = []
    /// The project the `changedFilePaths` set was captured for. The surface drops the set
    /// when a different project becomes the active context (mirrors the branch chip), so a
    /// stale changed-set never boosts the wrong project's mentions across a switch.
    public internal(set) var changedFilePathsProjectID: UUID?
    /// In-memory front buffer for per-thread composer drafts during rapid thread switches.
    /// `ChatThread.composerDraft` is the cross-launch source of truth.
    public internal(set) var threadDrafts: [UUID: String] = [:]
    /// The thread whose morning-triage return digest card is currently open (issue #877), or nil when no
    /// digest is showing. Session-only presentation state; the digest content itself is rebuilt from the
    /// thread's persisted records on every surface pass.
    public internal(set) var attentionDigestThreadID: UUID?
    /// The morning-triage Attention section's PREVIEW cursor — which row j/k highlight (issue #877).
    /// This is deliberately a SEPARATE, session-only, navigation-only field: moving the cursor is a
    /// preview, NOT "I have read this thread." It must never touch the workspace thread selection or any
    /// return watermark — only an explicit open (Enter / click → digest) does that. Keeping it distinct
    /// is what prevents j/k from zeroing the passed-over threads' unseen-turn badges. Nil means "no
    /// explicit cursor yet" — the pure model then defaults it to the first (highest-severity) row.
    public internal(set) var attentionCursorID: UUID?

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        chrome: WorkspaceChromeState = WorkspaceChromeState(),
        navigationHistory: WorkspaceNavigationHistoryState = WorkspaceNavigationHistoryState(),
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
        sidebarSavedSearchStore: JSONSidebarSavedSearchStore? = nil,
        permissionRuleStore: PermissionRuleFileStore? = nil,
        globalMemoryDirectory: URL? = nil,
        computerUseBackend: (any ComputerUseBackend)? = nil,
        sshRemoteShellExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor(),
        mcpSecretStore: (any MCPSecretStore)? = nil
    ) {
        self.root = root
        self.chrome = chrome
        self.navigationHistory = navigationHistory
        self.composer = composer
        self.terminal = terminal
        self.browser = browser
        self.extensions = extensions
        self.memories = memories
        self.activity = activity
        self.automations = automations
        self.pullRequestReviewDraft = pullRequestReviewDraft
        self.sidebarFilter = sidebarFilter
        self.sidebarSavedSearches = JSONSidebarSavedSearchStore.normalized(sidebarSavedSearches)
        self.activeSidebarSavedSearchID = self.sidebarSavedSearches.contains { $0.id == activeSidebarSavedSearchID }
            ? activeSidebarSavedSearchID
            : nil
        self.sidebarSelection = sidebarSelection
        self.runner = runner
        // Subagent-worker calls are one-shot auxiliary housekeeping: LLMWorkspaceSubagentWorker.run
        // issues a single tool-free nextAction on a fresh, unique-prompt ChatThread that is never
        // re-sent, so a prompt-cache breakpoint on it could only ever be a cache WRITE with no read
        // (a pure cost premium) — the same class as the context-summary path RuntimeFactory
        // disables. Opt this path out too; a non-caching client (e.g. the mock) is passed through
        // untouched.
        self.subagentScheduler = WorkspaceSubagentScheduler(
            worker: LLMWorkspaceSubagentWorker.scheduledWorker(
                llm: disablingPromptCachingIfSupported(runner.llm)
            )
        )
        self.contextSummaryGenerator = contextSummaryGenerator
        self.threadPersistence = WorkspaceThreadPersistence(store: threadStore)
        self.projectStore = projectStore
        self.automationStore = automationStore
        self.sidebarSavedSearchStore = sidebarSavedSearchStore
        self.permissionRuleStore = permissionRuleStore
        self.globalMemoryDirectory = globalMemoryDirectory
        self.computerUseBackend = computerUseBackend
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.mcpRuntime = WorkspaceMCPRuntime(
            launcher: DefaultWorkspaceMCPServerLauncher(secretStore: mcpSecretStore)
        )
        if let computerUseBackend {
            self.root.topBar.computerUseStatus = computerUseBackend.status
        }
        restorePersistedSelectedComposerDraftIfNeeded()
        syncTerminalSessionToSelectedProject()
        refreshTopBar()
        refreshFileMentionIndex()
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

    public func setComputerUseForegroundApplication(_ application: ComputerUseApplication?) {
        root.topBar.computerUseForegroundApplication = application
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    /// Records the latest git branch/ahead-behind status for a project, surfaced as
    /// a top-bar chip. Tagged with the project it came from so `refreshTopBar` drops
    /// it once a different project is selected (no stale branch after a switch). The
    /// caller is expected to `refreshTopBar` afterward.
    func setBranchStatus(_ status: GitBranchStatus?, forProjectID projectID: UUID?) {
        root.topBar.branchStatus = status
        root.topBar.branchStatusProjectID = status == nil ? nil : projectID
    }

    /// Records the changed-file set captured from a `git status` run, tagged with the
    /// project it ran for. The surface only applies the boost while that project is the
    /// active mention context, so a status completing after a project switch is harmless.
    func setChangedFilePaths(_ paths: Set<String>, forProjectID projectID: UUID?) {
        changedFilePaths = paths
        changedFilePathsProjectID = projectID
    }

    /// The changed-file set, but only when it was captured for the project the file index
    /// is currently built from (`root.selectedProjectID` — the same notion as
    /// `activeWorkspaceRoot`); empty otherwise so a stale set never boosts another
    /// project's `@` suggestions on any switch path that doesn't rebuild the index.
    var activeChangedFilePaths: Set<String> {
        changedFilePathsProjectID == root.selectedProjectID ? changedFilePaths : []
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
        let previousResolutions = instructionDiagnosticResolutions(for: id)
        WorkspaceProjectContextRefresher.refreshLocalProjectMetadata(
            projectID: id,
            projects: &root.projects
        )
        let currentResolutions = instructionDiagnosticResolutions(for: id)
        if currentResolutions != previousResolutions {
            saveProjects()
        }
        refreshFileMentionIndex()
    }

    private func instructionDiagnosticResolutions(for projectID: UUID?) -> [ProjectInstructionDiagnosticResolution] {
        projectID
            .flatMap { id in root.projects.first { $0.id == id } }
            .map(\.instructionDiagnosticResolutions) ?? []
    }

    /// Recomputes the cached composer file-mention index from the selected local
    /// project. Remote or unselected projects clear the index so mentions stay empty.
    func refreshFileMentionIndex() {
        // The changed-file set is captured from a git status; any index rebuild (which
        // happens on every tool run via refreshProjectMetadata) invalidates it so a
        // file that was committed/cleaned is never left badged. The git-status run
        // re-sets it immediately after this rebuild, so the badge survives that run.
        changedFilePaths = []
        changedFilePathsProjectID = nil
        guard let activeWorkspaceRoot else {
            fileMentionIndex = WorkspaceFileIndex()
            return
        }
        fileMentionIndex = WorkspaceFileIndexer(workspaceRoot: activeWorkspaceRoot).index()
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

    func saveSidebarSavedSearches() {
        try? sidebarSavedSearchStore?.save(sidebarSavedSearches)
    }

}
