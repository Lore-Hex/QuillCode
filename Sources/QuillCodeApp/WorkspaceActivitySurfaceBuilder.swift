import QuillCodeCore

enum WorkspaceActivitySurfaceBuilder {
    static func subtitle(toolCount: Int, sourceCount: Int, artifactCount: Int) -> String {
        [
            WorkspaceActivityText.countLabel(toolCount, singular: "tool"),
            WorkspaceActivityText.countLabel(sourceCount, singular: "source"),
            WorkspaceActivityText.countLabel(artifactCount, singular: "artifact")
        ].joined(separator: " - ")
    }

    static func taskTitle(for thread: ChatThread) -> String {
        guard let latestUserMessage = thread.messages.reversed().first(where: { $0.role == .user }) else {
            return thread.title
        }
        return WorkspaceActivityText.boundedLine(latestUserMessage.content, limit: 96)
    }

    static func recentSteps(for thread: ChatThread) -> [ActivityItemSurface] {
        WorkspaceActivityEventSurfaceBuilder.recentSteps(for: thread)
    }

    static func toolItems(from toolCards: [ToolCardState]) -> [ActivityItemSurface] {
        toolCards
            .suffix(8)
            .map { card in
                ActivityItemSurface(
                    id: card.id,
                    title: card.title,
                    detail: WorkspaceActivityText.boundedLine(card.subtitle, limit: 120),
                    kind: "tool",
                    statusLabel: card.status.rawValue
                )
            }
    }

    static func sourceItems(instructions: [ProjectInstruction], memories: [MemoryNote]) -> [ActivityItemSurface] {
        WorkspaceActivitySourceSurfaceBuilder.items(instructions: instructions, memories: memories)
    }

    static func uniqueArtifacts(from toolCards: [ToolCardState]) -> [ToolArtifactState] {
        var seen = Set<String>()
        var artifacts: [ToolArtifactState] = []
        for artifact in toolCards.flatMap(\.artifacts).reversed() {
            guard seen.insert(artifact.value).inserted else { continue }
            artifacts.append(artifact)
            if artifacts.count == 8 { break }
        }
        return Array(artifacts.reversed())
    }

    static func sections(
        planItems: [ActivityItemSurface],
        recentSteps: [ActivityItemSurface],
        subagents: [ActivityItemSurface],
        tools: [ActivityItemSurface],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        handoffSummary: String?,
        collapsedSectionIDs: Set<ActivitySectionKind>
    ) -> [ActivitySectionSurface] {
        let instructionConflicts = instructionConflictItems(from: sources)
        return [
            ActivitySectionSurface(
                kind: .plan,
                items: planItems,
                isCollapsed: collapsedSectionIDs.contains(.plan)
            ),
            ActivitySectionSurface(
                kind: .recent,
                items: recentSteps,
                isCollapsed: collapsedSectionIDs.contains(.recent)
            ),
            ActivitySectionSurface(
                kind: .subagents,
                items: subagents,
                isCollapsed: collapsedSectionIDs.contains(.subagents)
            ),
            ActivitySectionSurface(
                kind: .handoff,
                bodyText: handoffSummary,
                isCollapsed: collapsedSectionIDs.contains(.handoff)
            ),
            ActivitySectionSurface(
                kind: .tools,
                items: tools,
                isCollapsed: collapsedSectionIDs.contains(.tools)
            ),
            ActivitySectionSurface(
                kind: .instructionReview,
                items: instructionConflicts,
                isCollapsed: collapsedSectionIDs.contains(.instructionReview)
            ),
            ActivitySectionSurface(
                kind: .sources,
                items: sources,
                isCollapsed: collapsedSectionIDs.contains(.sources)
            ),
            ActivitySectionSurface(
                kind: .artifacts,
                artifacts: artifacts,
                isCollapsed: collapsedSectionIDs.contains(.artifacts)
            ),
            ActivitySectionSurface(
                kind: .latestAnswer,
                bodyText: finalAnswer,
                isCollapsed: collapsedSectionIDs.contains(.latestAnswer)
            )
        ].filter { !$0.isEmpty || $0.kind.alwaysVisible }
    }

    static func instructionConflictItems(from sources: [ActivityItemSurface]) -> [ActivityItemSurface] {
        sources.filter {
            $0.kind == "instruction-diagnostic" && $0.statusLabel == "conflict"
        }
    }

    static func planItems(
        for thread: ChatThread,
        toolCards: [ToolCardState],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        agentStatus: String
    ) -> [ActivityItemSurface] {
        WorkspaceActivityPlanSurfaceBuilder.fallbackItems(
            for: thread,
            toolCards: toolCards,
            sources: sources,
            artifacts: artifacts,
            finalAnswer: finalAnswer,
            agentStatus: agentStatus
        )
    }

    static func authoredPlanItems(for thread: ChatThread) -> [ActivityItemSurface]? {
        WorkspaceActivityPlanSurfaceBuilder.authoredItems(for: thread)
    }

    static func subagentItems(for thread: ChatThread) -> [ActivityItemSurface] {
        SubagentProgressToolExecutor.activityItems(for: thread)
    }

    static func handoffSummary(
        for thread: ChatThread,
        toolCards: [ToolCardState],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        agentStatus: String
    ) -> String {
        if let update = HandoffUpdateToolExecutor.latestUpdate(in: thread) {
            return HandoffUpdateToolExecutor.displayText(for: update)
        }
        return WorkspaceActivityHandoffSummaryBuilder.summary(
            for: thread,
            latestRequestTitle: taskTitle(for: thread),
            toolCards: toolCards,
            sources: sources,
            artifacts: artifacts,
            finalAnswer: finalAnswer,
            agentStatus: agentStatus
        )
    }

    static func finalAnswer(for thread: ChatThread) -> String? {
        guard let answer = thread.messages.reversed().first(where: { $0.role == .assistant })?.content else {
            return nil
        }
        return WorkspaceActivityText.boundedLine(answer, limit: 280)
    }
}
