import QuillCodeCore

enum WorkspaceActivityPlanSurfaceBuilder {
    static func fallbackItems(
        for thread: ChatThread,
        toolCards: [ToolCardState],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        agentStatus: String
    ) -> [ActivityItemSurface] {
        let latestRequest = thread.messages.reversed().first(where: { $0.role == .user })?.content
        let toolStatus = aggregateToolStatus(toolCards)
        let answerStatus = finalAnswer == nil
            ? (isActive(agentStatus) ? ActivityStatusLabel.running : ActivityStatusLabel.pending)
            : ActivityStatusLabel.done
        let review = reviewState(toolCards: toolCards, artifacts: artifacts, finalAnswer: finalAnswer)

        return [
            ActivityItemSurface(
                id: "plan-request",
                title: "Understand request",
                detail: latestRequest.map { WorkspaceActivityText.boundedLine($0, limit: 120) }
                    ?? "Waiting for the first user request.",
                kind: "plan",
                statusLabel: latestRequest == nil ? ActivityStatusLabel.pending : ActivityStatusLabel.done
            ),
            ActivityItemSurface(
                id: "plan-context",
                title: "Load context",
                detail: sources.isEmpty
                    ? "No instruction or memory sources attached."
                    : "\(WorkspaceActivityText.countLabel(sources.count, singular: "source")) attached.",
                kind: "plan",
                statusLabel: sources.isEmpty ? ActivityStatusLabel.optional : ActivityStatusLabel.done
            ),
            ActivityItemSurface(
                id: "plan-tools",
                title: "Use tools",
                detail: toolPlanDetail(toolCards),
                kind: "plan",
                statusLabel: toolStatus
            ),
            ActivityItemSurface(
                id: "plan-review",
                title: "Review results",
                detail: review.detail,
                kind: "plan",
                statusLabel: review.status
            ),
            ActivityItemSurface(
                id: "plan-answer",
                title: "Answer user",
                detail: finalAnswer.map { WorkspaceActivityText.boundedLine($0, limit: 140) }
                    ?? "Waiting for the final assistant response.",
                kind: "plan",
                statusLabel: answerStatus
            )
        ]
    }

    static func authoredItems(for thread: ChatThread) -> [ActivityItemSurface]? {
        guard let update = PlanUpdateToolExecutor.latestUpdate(in: thread) else {
            return nil
        }

        let explanation = update.explanation.map { WorkspaceActivityText.boundedLine($0, limit: 160) }
        let items = update.plan.enumerated().map { index, item in
            ActivityItemSurface(
                id: "authored-plan-\(index)",
                title: WorkspaceActivityText.boundedLine(item.step, limit: 120),
                detail: item.detail.map { WorkspaceActivityText.boundedLine($0, limit: 160) }
                    ?? (index == 0 ? explanation : nil)
                    ?? "Model-authored task plan.",
                kind: "authored-plan",
                statusLabel: item.status.label
            )
        }

        return items.isEmpty ? nil : items
    }

    private static func reviewState(
        toolCards: [ToolCardState],
        artifacts: [ToolArtifactState],
        finalAnswer: String?
    ) -> (status: String, detail: String) {
        if toolCards.contains(where: { $0.status == .failed }) {
            return (ActivityStatusLabel.review, "One or more tool calls failed and needs attention.")
        }
        if finalAnswer != nil || toolCards.contains(where: { $0.status == .done }) {
            let detail = artifacts.isEmpty
                ? "Reviewed completed tool results."
                : "Reviewed \(WorkspaceActivityText.countLabel(artifacts.count, singular: "artifact"))."
            return (ActivityStatusLabel.done, detail)
        }
        return (ActivityStatusLabel.pending, "Waiting for tool output or a final answer.")
    }

    private static func aggregateToolStatus(_ toolCards: [ToolCardState]) -> String {
        guard !toolCards.isEmpty else { return ActivityStatusLabel.optional }
        if toolCards.contains(where: { $0.status == .failed }) { return ActivityStatusLabel.failed }
        if toolCards.contains(where: { $0.status == .running }) { return ActivityStatusLabel.running }
        if toolCards.contains(where: { $0.status == .queued || $0.status == .review }) { return ActivityStatusLabel.queued }
        return ActivityStatusLabel.done
    }

    private static func toolPlanDetail(_ toolCards: [ToolCardState]) -> String {
        guard !toolCards.isEmpty else {
            return "No tool use needed yet."
        }
        let names = toolCards.suffix(3)
            .map { WorkspaceToolDisplayNameBuilder.displayName(for: $0.title) }
            .joined(separator: ", ")
        return "\(WorkspaceActivityText.countLabel(toolCards.count, singular: "tool")): \(names)"
    }

    private static func isActive(_ agentStatus: String) -> Bool {
        // Single source of truth, shared with the composer plan-progress rail so a run's liveness can
        // never drift between the two surfaces. (Behavior-identical to the previous inline predicate.)
        AgentStatusClassifier.isActive(agentStatus)
    }
}
