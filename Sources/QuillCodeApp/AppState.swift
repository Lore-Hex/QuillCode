import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillComputerUseKit

public struct SidebarItem: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var isPinned: Bool
    public var isArchived: Bool

    public init(thread: ChatThread) {
        self.id = thread.id
        self.title = thread.title
        self.subtitle = thread.model
        self.isPinned = thread.isPinned
        self.isArchived = thread.isArchived
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

    public init(
        appName: String = "QuillCode",
        projectName: String? = nil,
        threadTitle: String? = nil,
        model: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        agentStatus: String = "Idle",
        computerUseStatus: ComputerUseStatus = .init(
            available: false,
            screenRecordingGranted: false,
            accessibilityGranted: false,
            message: "Computer Use setup needed."
        )
    ) {
        self.appName = appName
        self.projectName = projectName
        self.threadTitle = threadTitle
        self.model = model
        self.mode = mode
        self.agentStatus = agentStatus
        self.computerUseStatus = computerUseStatus
    }
}

public struct QuillCodeRootState: Sendable, Hashable {
    public var config: AppConfig
    public var projects: [ProjectRef]
    public var threads: [ChatThread]
    public var selectedThreadID: UUID?
    public var topBar: TopBarState
    public var modelCatalog: [ModelInfo]

    public init(
        config: AppConfig = AppConfig(),
        projects: [ProjectRef] = [],
        threads: [ChatThread] = [],
        selectedThreadID: UUID? = nil,
        topBar: TopBarState = TopBarState(),
        modelCatalog: [ModelInfo] = TrustedRouterModelCatalog.defaultModels
    ) {
        self.config = config
        self.projects = projects
        self.threads = threads
        self.selectedThreadID = selectedThreadID
        self.topBar = topBar
        self.modelCatalog = modelCatalog
    }

    public var sidebarItems: [SidebarItem] {
        threads
            .filter { !$0.isArchived }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
            .map(SidebarItem.init)
    }
}
