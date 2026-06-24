import Foundation
import QuillCodeCore

public struct WorkspaceActivitySurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var statusLabel: String
    public var taskTitle: String
    public var taskSubtitle: String
    public var planItems: [ActivityItemSurface]
    public var recentSteps: [ActivityItemSurface]
    public var tools: [ActivityItemSurface]
    public var sources: [ActivityItemSurface]
    public var artifacts: [ToolArtifactState]
    public var finalAnswer: String?
    public var handoffSummary: String?
    public var sections: [ActivitySectionSurface]

    public init(
        isVisible: Bool = false,
        title: String = "Activity",
        subtitle: String = "No active thread",
        statusLabel: String = "Idle",
        taskTitle: String = "No task selected",
        taskSubtitle: String = "Start a chat to see task progress, tools, sources, and artifacts.",
        planItems: [ActivityItemSurface] = [],
        recentSteps: [ActivityItemSurface] = [],
        tools: [ActivityItemSurface] = [],
        sources: [ActivityItemSurface] = [],
        artifacts: [ToolArtifactState] = [],
        finalAnswer: String? = nil,
        handoffSummary: String? = nil,
        collapsedSectionIDs: Set<ActivitySectionKind> = []
    ) {
        self.isVisible = isVisible
        self.title = title
        self.subtitle = subtitle
        self.statusLabel = statusLabel
        self.taskTitle = taskTitle
        self.taskSubtitle = taskSubtitle
        self.planItems = planItems
        self.recentSteps = recentSteps
        self.tools = tools
        self.sources = sources
        self.artifacts = artifacts
        self.finalAnswer = finalAnswer
        self.handoffSummary = handoffSummary
        self.sections = WorkspaceActivitySurfaceBuilder.sections(
            planItems: planItems,
            recentSteps: recentSteps,
            tools: tools,
            sources: sources,
            artifacts: artifacts,
            finalAnswer: finalAnswer,
            handoffSummary: handoffSummary,
            collapsedSectionIDs: collapsedSectionIDs
        )
    }

    public init(
        isVisible: Bool,
        thread: ChatThread?,
        toolCards: [ToolCardState],
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        agentStatus: String,
        collapsedSectionIDs: Set<ActivitySectionKind> = []
    ) {
        guard let thread else {
            self.init(
                isVisible: isVisible,
                statusLabel: agentStatus,
                collapsedSectionIDs: collapsedSectionIDs
            )
            return
        }

        let sources = WorkspaceActivitySurfaceBuilder.sourceItems(instructions: instructions, memories: memories)
        let artifacts = WorkspaceActivitySurfaceBuilder.uniqueArtifacts(from: toolCards)
        let finalAnswer = WorkspaceActivitySurfaceBuilder.finalAnswer(for: thread)
        let planItems = WorkspaceActivitySurfaceBuilder.authoredPlanItems(for: thread)
            ?? WorkspaceActivitySurfaceBuilder.planItems(
                for: thread,
                toolCards: toolCards,
                sources: sources,
                artifacts: artifacts,
                finalAnswer: finalAnswer,
                agentStatus: agentStatus
            )
        self.init(
            isVisible: isVisible,
            title: "Activity",
            subtitle: WorkspaceActivitySurfaceBuilder.subtitle(
                toolCount: toolCards.count,
                sourceCount: sources.count,
                artifactCount: artifacts.count
            ),
            statusLabel: agentStatus,
            taskTitle: WorkspaceActivitySurfaceBuilder.taskTitle(for: thread),
            taskSubtitle: "\(thread.messages.count) message\(thread.messages.count == 1 ? "" : "s") - \(thread.events.count) event\(thread.events.count == 1 ? "" : "s")",
            planItems: planItems,
            recentSteps: WorkspaceActivitySurfaceBuilder.recentSteps(for: thread),
            tools: WorkspaceActivitySurfaceBuilder.toolItems(from: toolCards),
            sources: sources,
            artifacts: artifacts,
            finalAnswer: finalAnswer,
            handoffSummary: WorkspaceActivitySurfaceBuilder.handoffSummary(
                for: thread,
                toolCards: toolCards,
                sources: sources,
                artifacts: artifacts,
                finalAnswer: finalAnswer,
                agentStatus: agentStatus
            ),
            collapsedSectionIDs: collapsedSectionIDs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case title
        case subtitle
        case statusLabel
        case taskTitle
        case taskSubtitle
        case planItems
        case recentSteps
        case tools
        case sources
        case artifacts
        case finalAnswer
        case handoffSummary
        case sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Activity"
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? "No active thread"
        self.statusLabel = try container.decodeIfPresent(String.self, forKey: .statusLabel) ?? "Idle"
        self.taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle) ?? "No task selected"
        self.taskSubtitle = try container.decodeIfPresent(String.self, forKey: .taskSubtitle)
            ?? "Start a chat to see task progress, tools, sources, and artifacts."
        self.planItems = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .planItems) ?? []
        self.recentSteps = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .recentSteps) ?? []
        self.tools = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .tools) ?? []
        self.sources = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .sources) ?? []
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.finalAnswer = try container.decodeIfPresent(String.self, forKey: .finalAnswer)
        self.handoffSummary = try container.decodeIfPresent(String.self, forKey: .handoffSummary)
        self.sections = try container.decodeIfPresent([ActivitySectionSurface].self, forKey: .sections)
            ?? WorkspaceActivitySurfaceBuilder.sections(
                planItems: planItems,
                recentSteps: recentSteps,
                tools: tools,
                sources: sources,
                artifacts: artifacts,
                finalAnswer: finalAnswer,
                handoffSummary: handoffSummary,
                collapsedSectionIDs: []
            )
    }
}
