import Foundation
import QuillCodeCore

public struct WorkspaceActivitySurface: Codable, Sendable, Hashable {
    public private(set) var isVisible: Bool
    public private(set) var title: String
    public private(set) var subtitle: String
    public private(set) var statusLabel: String
    public private(set) var taskTitle: String
    public private(set) var taskSubtitle: String
    public private(set) var planItems: [ActivityItemSurface]
    public private(set) var contextItems: [ActivityItemSurface]
    public private(set) var recentSteps: [ActivityItemSurface]
    public private(set) var subagents: [ActivityItemSurface]
    public private(set) var tools: [ActivityItemSurface]
    public private(set) var sources: [ActivityItemSurface]
    public private(set) var artifacts: [ToolArtifactState]
    public private(set) var finalAnswer: String?
    public private(set) var handoffSummary: String?
    public private(set) var sections: [ActivitySectionSurface]

    public init(
        isVisible: Bool = false,
        title: String = "Activity",
        subtitle: String = "No active thread",
        statusLabel: String = "Idle",
        taskTitle: String = "No task selected",
        taskSubtitle: String = "Start a chat to see task progress, tools, sources, and artifacts.",
        planItems: [ActivityItemSurface] = [],
        changeItems: [ActivityItemSurface] = [],
        contextItems: [ActivityItemSurface] = [],
        recentSteps: [ActivityItemSurface] = [],
        subagents: [ActivityItemSurface] = [],
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
        self.contextItems = contextItems
        self.recentSteps = recentSteps
        self.subagents = subagents
        self.tools = tools
        self.sources = sources
        self.artifacts = artifacts
        self.finalAnswer = finalAnswer
        self.handoffSummary = handoffSummary
        self.sections = WorkspaceActivitySurfaceBuilder.sections(
            planItems: planItems,
            changeItems: changeItems,
            contextItems: contextItems,
            recentSteps: recentSteps,
            subagents: subagents,
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
        changeFiles: [WorkspaceReviewFileSurface] = [],
        collapsedSectionIDs: Set<ActivitySectionKind> = [],
        dismissedInstructionDiagnosticIDs: Set<String> = []
    ) {
        guard let thread else {
            self.init(
                isVisible: isVisible,
                statusLabel: agentStatus,
                collapsedSectionIDs: collapsedSectionIDs
            )
            return
        }

        let sources = WorkspaceActivitySurfaceBuilder.sourceItems(
            instructions: instructions,
            memories: memories,
            dismissedInstructionDiagnosticIDs: dismissedInstructionDiagnosticIDs
        )
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
            taskSubtitle: Self.threadCountSubtitle(thread),
            planItems: planItems,
            changeItems: WorkspaceActivityChangesSurfaceBuilder.items(from: changeFiles),
            contextItems: WorkspaceActivitySurfaceBuilder.contextItems(for: thread),
            recentSteps: WorkspaceActivitySurfaceBuilder.recentSteps(for: thread),
            subagents: WorkspaceActivitySurfaceBuilder.subagentItems(for: thread),
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
        case contextItems
        case recentSteps
        case subagents
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
        self.contextItems = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .contextItems) ?? []
        self.recentSteps = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .recentSteps) ?? []
        self.subagents = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .subagents) ?? []
        self.tools = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .tools) ?? []
        self.sources = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .sources) ?? []
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.finalAnswer = try container.decodeIfPresent(String.self, forKey: .finalAnswer)
        self.handoffSummary = try container.decodeIfPresent(String.self, forKey: .handoffSummary)
        self.sections = try container.decodeIfPresent([ActivitySectionSurface].self, forKey: .sections)
            ?? WorkspaceActivitySurfaceBuilder.sections(
                planItems: planItems,
                contextItems: contextItems,
                recentSteps: recentSteps,
                subagents: subagents,
                tools: tools,
                sources: sources,
                artifacts: artifacts,
                finalAnswer: finalAnswer,
                handoffSummary: handoffSummary,
                collapsedSectionIDs: []
            )
    }

    private static func threadCountSubtitle(_ thread: ChatThread) -> String {
        [
            Self.count(thread.messages.count, singular: "message"),
            Self.count(thread.events.count, singular: "event")
        ].joined(separator: " - ")
    }

    private static func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }
}
