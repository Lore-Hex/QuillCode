import Foundation
import QuillCodeCore

public struct WorkspaceSurface: Codable, Sendable, Hashable {
    public var topBar: TopBarSurface
    public var sidebar: SidebarSurface
    public var transcript: TranscriptSurface
    public var composer: ComposerSurface
    public var commands: [WorkspaceCommandSurface]
    public var lastError: String?

    public init(
        topBar: TopBarSurface,
        sidebar: SidebarSurface,
        transcript: TranscriptSurface,
        composer: ComposerSurface,
        commands: [WorkspaceCommandSurface],
        lastError: String? = nil
    ) {
        self.topBar = topBar
        self.sidebar = sidebar
        self.transcript = transcript
        self.composer = composer
        self.commands = commands
        self.lastError = lastError
    }
}

public struct TopBarSurface: Codable, Sendable, Hashable {
    public var appName: String
    public var primaryTitle: String
    public var subtitle: String
    public var modelLabel: String
    public var selectedModelID: String
    public var modelCategories: [ModelCategorySurface]
    public var modeLabel: String
    public var agentStatus: String
    public var computerUseLabel: String
    public var showsComputerUseSetup: Bool

    public init(
        appName: String,
        primaryTitle: String,
        subtitle: String,
        modelLabel: String,
        selectedModelID: String,
        modelCategories: [ModelCategorySurface],
        modeLabel: String,
        agentStatus: String,
        computerUseLabel: String,
        showsComputerUseSetup: Bool
    ) {
        self.appName = appName
        self.primaryTitle = primaryTitle
        self.subtitle = subtitle
        self.modelLabel = modelLabel
        self.selectedModelID = selectedModelID
        self.modelCategories = modelCategories
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
        self.computerUseLabel = computerUseLabel
        self.showsComputerUseSetup = showsComputerUseSetup
    }
}

public struct ModelCategorySurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { category }
    public var category: String
    public var models: [ModelOptionSurface]

    public init(category: String, models: [ModelOptionSurface]) {
        self.category = category
        self.models = models
    }
}

public struct ModelOptionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String
    public var isSelected: Bool

    public init(model: ModelInfo, selectedModelID: String) {
        self.id = model.id
        self.provider = model.provider
        self.displayName = model.displayName
        self.category = model.category
        self.isSelected = model.id == selectedModelID
    }
}

public struct SidebarSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [SidebarItemSurface]
    public var selectedThreadID: UUID?
    public var emptyTitle: String

    public init(
        title: String = "Chats",
        items: [SidebarItemSurface],
        selectedThreadID: UUID?,
        emptyTitle: String = "No chats yet"
    ) {
        self.title = title
        self.items = items
        self.selectedThreadID = selectedThreadID
        self.emptyTitle = emptyTitle
    }
}

public struct SidebarItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var isSelected: Bool
    public var isPinned: Bool

    public init(item: SidebarItem, selectedThreadID: UUID?) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.isSelected = item.id == selectedThreadID
        self.isPinned = item.isPinned
    }
}

public struct TranscriptSurface: Codable, Sendable, Hashable {
    public var messages: [MessageSurface]
    public var toolCards: [ToolCardState]
    public var emptyTitle: String
    public var emptySubtitle: String

    public init(
        messages: [MessageSurface],
        toolCards: [ToolCardState],
        emptyTitle: String = "Ask QuillCode to inspect, edit, or run this project.",
        emptySubtitle: String = "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration."
    ) {
        self.messages = messages
        self.toolCards = toolCards
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
    }
}

public struct MessageSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var accessibilityLabel: String

    public init(message: ChatMessage) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)"
    }
}

public struct ComposerSurface: Codable, Sendable, Hashable {
    public var draft: String
    public var placeholder: String
    public var isSending: Bool
    public var canSend: Bool

    public init(composer: ComposerState) {
        self.draft = composer.draft
        self.placeholder = composer.placeholder
        self.isSending = composer.isSending
        self.canSend = !composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !composer.isSending
    }
}

public struct WorkspaceCommandSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var shortcut: String?
    public var isEnabled: Bool

    public init(id: String, title: String, shortcut: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }
}

@MainActor
public extension QuillCodeWorkspaceModel {
    func surface() -> WorkspaceSurface {
        let thread = selectedThread
        let topBarState = root.topBar
        let computerUse = topBarState.computerUseStatus
        return WorkspaceSurface(
            topBar: TopBarSurface(
                appName: topBarState.appName,
                primaryTitle: thread?.title ?? "QuillCode",
                subtitle: topBarSubtitle(thread: thread),
                modelLabel: modelLabel(for: topBarState.model),
                selectedModelID: topBarState.model,
                modelCategories: modelCategories(selectedModelID: topBarState.model),
                modeLabel: Self.modeLabel(topBarState.mode),
                agentStatus: topBarState.agentStatus,
                computerUseLabel: computerUse.available ? "Computer Use ready" : "Computer Use setup needed",
                showsComputerUseSetup: !computerUse.available
            ),
            sidebar: SidebarSurface(
                items: root.sidebarItems.map { SidebarItemSurface(item: $0, selectedThreadID: root.selectedThreadID) },
                selectedThreadID: root.selectedThreadID
            ),
            transcript: TranscriptSurface(
                messages: (thread?.messages ?? []).map(MessageSurface.init),
                toolCards: currentToolCards
            ),
            composer: ComposerSurface(composer: composer),
            commands: commands(),
            lastError: lastError
        )
    }

    private func topBarSubtitle(thread: ChatThread?) -> String {
        let projectName = root.topBar.projectName ?? "No project"
        guard let thread else {
            return "\(projectName) - Not started"
        }
        return "\(projectName) - \(Self.modeLabel(thread.mode)) - \(thread.model)"
    }

    private func modelLabel(for id: String) -> String {
        guard let model = root.modelCatalog.first(where: { $0.id == id }) else {
            return id
        }
        if model.provider == "trustedrouter" {
            return model.id
        }
        return "\(model.provider)/\(model.displayName)"
    }

    private func modelCategories(selectedModelID: String) -> [ModelCategorySurface] {
        var catalog = root.modelCatalog
        if !catalog.contains(where: { $0.id == selectedModelID }) {
            catalog.insert(Self.fallbackModelInfo(for: selectedModelID), at: 0)
        }

        let options = catalog.map {
            ModelOptionSurface(model: $0, selectedModelID: selectedModelID)
        }
        return Dictionary(grouping: options, by: \.category)
            .map { category, models in
                ModelCategorySurface(
                    category: category,
                    models: models.sorted { lhs, rhs in
                        if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
                        return lhs.displayName < rhs.displayName
                    }
                )
            }
            .sorted {
                if $0.category == "Recommended" { return true }
                if $1.category == "Recommended" { return false }
                return $0.category < $1.category
            }
    }

    private static func fallbackModelInfo(for id: String) -> ModelInfo {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return ModelInfo(id: id, provider: parts[0], displayName: parts[1], category: "Current")
        }
        return ModelInfo(id: id, provider: "custom", displayName: id, category: "Current")
    }

    private func commands() -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(id: "new-chat", title: "New chat", shortcut: "Cmd+N"),
            WorkspaceCommandSurface(id: "search", title: "Search", shortcut: "Cmd+K"),
            WorkspaceCommandSurface(id: "stop-all", title: "Stop all", shortcut: "Esc", isEnabled: composer.isSending),
            WorkspaceCommandSurface(id: "settings", title: "Settings", shortcut: "Cmd+,"),
            WorkspaceCommandSurface(
                id: "computer-use-setup",
                title: "Computer Use setup",
                isEnabled: root.topBar.computerUseStatus.available == false
            )
        ]
    }

    static func modeLabel(_ mode: AgentMode) -> String {
        switch mode {
        case .readOnly:
            return "Read-only"
        case .review:
            return "Review"
        case .auto:
            return "Auto"
        }
    }
}
