import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

public struct SidebarItem: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var searchText: String
    public var updatedAt: Date
    public var isPinned: Bool
    public var isArchived: Bool
    public var worktree: SidebarItemWorktreeSummary?

    public init(thread: ChatThread) {
        self.id = thread.id
        self.title = thread.title
        self.subtitle = thread.model
        self.updatedAt = thread.updatedAt
        let combinedSearchText = thread.messages
            .filter { $0.role != .tool }
            .map(\.content)
            .joined(separator: "\n")
        self.searchText = String(combinedSearchText.prefix(8_000))
        self.isPinned = thread.isPinned
        self.isArchived = thread.isArchived
        self.worktree = thread.worktree.map { binding in
            let branch = binding.branch.trimmingCharacters(in: .whitespacesAndNewlines)
            return SidebarItemWorktreeSummary(
                branch: binding.branch,
                branchLeaf: branch.isEmpty
                    ? "Detached"
                    : branch.split(separator: "/").last.map(String.init) ?? branch,
                isResolvable: binding.isResolvable
            )
        }
    }
}

public struct TopBarState: Sendable, Hashable {
    public var appName: String
    public var projectName: String?
    public var threadTitle: String?
    public var model: String
    public var mode: AgentMode
    public var agentStatus: String
    public var computerUseStatus: ComputerUseStatus
    public var computerUseForegroundApplication: ComputerUseApplication?
    /// Branch + ahead/behind for the selected local/SSH project (or worktree),
    /// parsed from the latest `host.git.status` run. Nil until a status runs.
    public var branchStatus: GitBranchStatus?
    /// The project the `branchStatus` was captured for, so a refresh can drop it
    /// once a different project (or worktree) becomes selected — preventing a stale
    /// branch chip after switching projects via any path.
    public var branchStatusProjectID: UUID?

    public init(
        appName: String = "QuillCode",
        projectName: String? = nil,
        threadTitle: String? = nil,
        model: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        agentStatus: String = TopBarAgentStatusLabel.idle,
        computerUseStatus: ComputerUseStatus = .init(
            available: false,
            screenRecordingGranted: false,
            accessibilityGranted: false,
            message: "Needs Screen Recording + Accessibility"
        ),
        computerUseForegroundApplication: ComputerUseApplication? = nil,
        branchStatus: GitBranchStatus? = nil,
        branchStatusProjectID: UUID? = nil
    ) {
        self.appName = appName
        self.projectName = projectName
        self.threadTitle = threadTitle
        self.model = model
        self.mode = mode
        self.agentStatus = agentStatus
        self.computerUseStatus = computerUseStatus
        self.computerUseForegroundApplication = computerUseForegroundApplication
        self.branchStatus = branchStatus
        self.branchStatusProjectID = branchStatusProjectID
    }
}

public struct QuillCodeRootState: Sendable, Hashable {
    public var config: AppConfig
    public var projects: [ProjectRef]
    public var selectedProjectID: UUID?
    public var threads: [ChatThread]
    public var selectedThreadID: UUID?
    public var globalMemories: [MemoryNote]
    public var topBar: TopBarState
    public var modelCatalog: [ModelInfo]
    public var modelCatalogStatus: ModelCatalogStatus
    public var trustedRouterAPIKeyConfigured: Bool

    public init(
        config: AppConfig = AppConfig(),
        projects: [ProjectRef] = [],
        selectedProjectID: UUID? = nil,
        threads: [ChatThread] = [],
        selectedThreadID: UUID? = nil,
        globalMemories: [MemoryNote] = [],
        topBar: TopBarState = TopBarState(),
        modelCatalog: [ModelInfo] = TrustedRouterDefaults.normalizedModelCatalog([]),
        modelCatalogStatus: ModelCatalogStatus = .bundled,
        trustedRouterAPIKeyConfigured: Bool = false
    ) {
        self.config = config
        self.projects = projects
        self.selectedProjectID = selectedProjectID
        self.threads = threads
        self.selectedThreadID = selectedThreadID
        self.globalMemories = globalMemories
        self.topBar = topBar
        self.modelCatalog = modelCatalog
        self.modelCatalogStatus = modelCatalogStatus
        self.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured
    }

    public var sidebarItems: [SidebarItem] {
        threads
            .filter { !$0.isArchived }
            .sorted(by: Self.sidebarSort)
            .map(SidebarItem.init)
    }

    public var allSidebarItems: [SidebarItem] {
        threads
            .sorted {
                if $0.isArchived != $1.isArchived { return !$0.isArchived && $1.isArchived }
                return Self.sidebarSort($0, $1)
            }
            .map(SidebarItem.init)
    }

    private static func sidebarSort(_ lhs: ChatThread, _ rhs: ChatThread) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
        return lhs.updatedAt > rhs.updatedAt
    }
}
