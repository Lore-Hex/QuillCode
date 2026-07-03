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
    public private(set) var runReceiptItems: [ActivityItemSurface]
    public private(set) var recentSteps: [ActivityItemSurface]
    public private(set) var subagents: [ActivityItemSurface]
    public private(set) var tools: [ActivityItemSurface]
    public private(set) var sources: [ActivityItemSurface]
    public private(set) var artifacts: [ToolArtifactState]
    public private(set) var finalAnswer: String?
    public private(set) var handoffSummary: String?
    /// The run-integrity badge (VERIFIED / UNVERIFIED / RED) once the run's transcript has been scanned,
    /// else nil (a fresh / in-flight run has no verdict yet). The honesty stamp on the run.
    public private(set) var integrityBadge: RunIntegrityVerdict?
    /// The one-line reason behind the badge, for a tooltip / detail line. Empty when no badge.
    public private(set) var integrityDetail: String
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
        runReceiptItems: [ActivityItemSurface] = [],
        recentSteps: [ActivityItemSurface] = [],
        subagents: [ActivityItemSurface] = [],
        tools: [ActivityItemSurface] = [],
        sources: [ActivityItemSurface] = [],
        artifacts: [ToolArtifactState] = [],
        finalAnswer: String? = nil,
        handoffSummary: String? = nil,
        integrityBadge: RunIntegrityVerdict? = nil,
        integrityDetail: String = "",
        collapsedSectionIDs: Set<ActivitySectionKind> = []
    ) {
        self.isVisible = isVisible
        self.title = title
        self.subtitle = subtitle
        self.statusLabel = statusLabel
        self.taskTitle = taskTitle
        self.taskSubtitle = taskSubtitle
        self.integrityBadge = integrityBadge
        self.integrityDetail = integrityDetail
        self.planItems = planItems
        self.contextItems = contextItems
        self.runReceiptItems = runReceiptItems
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
            runReceiptItems: runReceiptItems,
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
        modelCatalog: [ModelInfo] = [],
        runSpendFuseUSD: Double? = 1.0,
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
        // Prefer a verdict already recorded on the thread (stable across reloads); the badge is nil for a
        // run that has not been scanned yet so the Activity header stays quiet until "finished".
        let integrity = RunIntegrityRecord.latest(in: thread)
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
            runReceiptItems: WorkspaceRunReceiptSurfaceBuilder(
                thread: thread,
                modelCatalog: modelCatalog,
                spendFuseUSD: runSpendFuseUSD
            ).items(),
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
            integrityBadge: integrity?.verdict,
            integrityDetail: integrity?.summary ?? "",
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
        case runReceiptItems
        case recentSteps
        case subagents
        case tools
        case sources
        case artifacts
        case finalAnswer
        case handoffSummary
        case integrityBadge
        case integrityDetail
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
        self.runReceiptItems = try container.decodeIfPresent(
            [ActivityItemSurface].self,
            forKey: .runReceiptItems
        ) ?? []
        self.recentSteps = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .recentSteps) ?? []
        self.subagents = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .subagents) ?? []
        self.tools = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .tools) ?? []
        self.sources = try container.decodeIfPresent([ActivityItemSurface].self, forKey: .sources) ?? []
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.finalAnswer = try container.decodeIfPresent(String.self, forKey: .finalAnswer)
        self.handoffSummary = try container.decodeIfPresent(String.self, forKey: .handoffSummary)
        self.integrityBadge = try container.decodeIfPresent(RunIntegrityVerdict.self, forKey: .integrityBadge)
        self.integrityDetail = try container.decodeIfPresent(String.self, forKey: .integrityDetail) ?? ""
        self.sections = try container.decodeIfPresent([ActivitySectionSurface].self, forKey: .sections)
            ?? WorkspaceActivitySurfaceBuilder.sections(
                planItems: planItems,
                contextItems: contextItems,
                runReceiptItems: runReceiptItems,
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
