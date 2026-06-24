import Foundation
import QuillCodeCore

enum WorkspaceActivitySurfaceBuilder {
    static func subtitle(toolCount: Int, sourceCount: Int, artifactCount: Int) -> String {
        [
            countLabel(toolCount, singular: "tool"),
            countLabel(sourceCount, singular: "source"),
            countLabel(artifactCount, singular: "artifact")
        ].joined(separator: " - ")
    }

    static func taskTitle(for thread: ChatThread) -> String {
        guard let latestUserMessage = thread.messages.reversed().first(where: { $0.role == .user }) else {
            return thread.title
        }
        return boundedLine(latestUserMessage.content, limit: 96)
    }

    static func recentSteps(for thread: ChatThread) -> [ActivityItemSurface] {
        thread.events
            .filter { $0.kind != .messageFeedback }
            .suffix(8)
            .map { event in
                ActivityItemSurface(
                    id: event.id.uuidString,
                    title: eventKindLabel(event.kind),
                    detail: boundedLine(event.summary, limit: 140),
                    kind: event.kind.rawValue,
                    statusLabel: eventStatusLabel(event.kind)
                )
            }
    }

    static func toolItems(from toolCards: [ToolCardState]) -> [ActivityItemSurface] {
        toolCards
            .suffix(8)
            .map { card in
                ActivityItemSurface(
                    id: card.id,
                    title: card.title,
                    detail: boundedLine(card.subtitle, limit: 120),
                    kind: "tool",
                    statusLabel: card.status.rawValue
                )
            }
    }

    static func sourceItems(instructions: [ProjectInstruction], memories: [MemoryNote]) -> [ActivityItemSurface] {
        let instructionItems = instructions.prefix(4).map { instruction in
            ActivityItemSurface(
                id: "instruction-\(instruction.path)",
                title: sourceTitle(instruction.path),
                detail: instruction.path,
                kind: "instruction",
                statusLabel: "rules"
            )
        }
        let memoryItems = memories.prefix(4).map { memory in
            ActivityItemSurface(
                id: "memory-\(memory.id)",
                title: memory.title,
                detail: memory.relativePath,
                kind: "memory",
                statusLabel: memory.scope.title
            )
        }
        return Array(instructionItems + memoryItems)
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
        tools: [ActivityItemSurface],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        handoffSummary: String?,
        collapsedSectionIDs: Set<ActivitySectionKind>
    ) -> [ActivitySectionSurface] {
        [
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

    static func finalAnswer(for thread: ChatThread) -> String? {
        guard let answer = thread.messages.reversed().first(where: { $0.role == .assistant })?.content else {
            return nil
        }
        return boundedLine(answer, limit: 280)
    }

    static func planItems(
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
        let reviewStatus: String
        let reviewDetail: String
        if toolCards.contains(where: { $0.status == .failed }) {
            reviewStatus = ActivityStatusLabel.review
            reviewDetail = "One or more tool calls failed and needs attention."
        } else if finalAnswer != nil || toolCards.contains(where: { $0.status == .done }) {
            reviewStatus = ActivityStatusLabel.done
            reviewDetail = artifacts.isEmpty
                ? "Reviewed completed tool results."
                : "Reviewed \(countLabel(artifacts.count, singular: "artifact"))."
        } else {
            reviewStatus = ActivityStatusLabel.pending
            reviewDetail = "Waiting for tool output or a final answer."
        }

        return [
            ActivityItemSurface(
                id: "plan-request",
                title: "Understand request",
                detail: latestRequest.map { boundedLine($0, limit: 120) } ?? "Waiting for the first user request.",
                kind: "plan",
                statusLabel: latestRequest == nil ? ActivityStatusLabel.pending : ActivityStatusLabel.done
            ),
            ActivityItemSurface(
                id: "plan-context",
                title: "Load context",
                detail: sources.isEmpty
                    ? "No instruction or memory sources attached."
                    : "\(countLabel(sources.count, singular: "source")) attached.",
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
                detail: reviewDetail,
                kind: "plan",
                statusLabel: reviewStatus
            ),
            ActivityItemSurface(
                id: "plan-answer",
                title: "Answer user",
                detail: finalAnswer.map { boundedLine($0, limit: 140) } ?? "Waiting for the final assistant response.",
                kind: "plan",
                statusLabel: answerStatus
            )
        ]
    }

    static func authoredPlanItems(for thread: ChatThread) -> [ActivityItemSurface]? {
        guard let update = PlanUpdateToolExecutor.latestUpdate(in: thread) else {
            return nil
        }

        let explanation = update.explanation.map { boundedLine($0, limit: 160) }
        let items = update.plan.enumerated().map { index, item in
            ActivityItemSurface(
                id: "authored-plan-\(index)",
                title: boundedLine(item.step, limit: 120),
                detail: item.detail.map { boundedLine($0, limit: 160) }
                    ?? (index == 0 ? explanation : nil)
                    ?? "Model-authored task plan.",
                kind: "authored-plan",
                statusLabel: item.status.label
            )
        }

        return items.isEmpty ? nil : items
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
        let names = toolCards.suffix(3).map(\.title).joined(separator: ", ")
        return "\(countLabel(toolCards.count, singular: "tool")): \(names)"
    }

    private static func isActive(_ agentStatus: String) -> Bool {
        let normalized = agentStatus.lowercased()
        return normalized.contains("running")
            || normalized.contains("streaming")
            || normalized.contains("queued")
            || normalized.contains("terminal")
    }

    static func handoffSummary(
        for thread: ChatThread,
        toolCards: [ToolCardState],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        agentStatus: String
    ) -> String {
        let toolNames = toolCards.suffix(4).map(\.title)
        let artifactLabels = artifacts.suffix(4).map(\.label)
        var lines = [
            "Thread: \(boundedLine(thread.title, limit: 80))",
            "Latest request: \(taskTitle(for: thread))",
            "Status: \(agentStatus)",
            "Tools: \(summary(count: toolCards.count, singular: "tool", details: toolNames))",
            "Sources: \(countLabel(sources.count, singular: "source"))",
            "Artifacts: \(summary(count: artifacts.count, singular: "artifact", details: artifactLabels))"
        ]
        if let finalAnswer {
            lines.append("Latest answer: \(boundedLine(finalAnswer, limit: 160))")
        }
        return lines.joined(separator: "\n")
    }

    private static func summary(count: Int, singular: String, details: [String]) -> String {
        guard count > 0 else { return "none" }
        let countText = countLabel(count, singular: singular)
        guard !details.isEmpty else { return countText }
        return "\(countText) (\(details.joined(separator: ", ")))"
    }

    private static func sourceTitle(_ path: String) -> String {
        let title = URL(fileURLWithPath: path).lastPathComponent
        return title.isEmpty ? path : title
    }

    private static func boundedLine(_ value: String, limit: Int) -> String {
        let normalized = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<end])..."
    }

    private static func eventKindLabel(_ kind: ThreadEventKind) -> String {
        switch kind {
        case .message:
            return "Message"
        case .toolQueued:
            return "Tool queued"
        case .toolRunning:
            return "Tool running"
        case .toolCompleted:
            return "Tool completed"
        case .toolFailed:
            return "Tool failed"
        case .approvalRequested:
            return "Safety check"
        case .approvalDecided:
            return "Safety decision"
        case .reviewComment:
            return "Review comment"
        case .notice:
            return "Notice"
        case .messageFeedback:
            return "Feedback"
        }
    }

    private static func eventStatusLabel(_ kind: ThreadEventKind) -> String {
        switch kind {
        case .toolQueued:
            return ActivityStatusLabel.queued
        case .toolRunning:
            return ActivityStatusLabel.running
        case .toolCompleted:
            return ActivityStatusLabel.done
        case .toolFailed:
            return ActivityStatusLabel.failed
        case .approvalRequested:
            return ActivityStatusLabel.review
        case .approvalDecided:
            return ActivityStatusLabel.checked
        case .message, .reviewComment, .notice, .messageFeedback:
            return ActivityStatusLabel.logged
        }
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

private enum ActivityStatusLabel {
    static let checked = "Checked"
    static let done = "Done"
    static let failed = "Failed"
    static let logged = "Logged"
    static let optional = "Optional"
    static let pending = "Pending"
    static let queued = "Queued"
    static let review = "Review"
    static let running = "Running"
}
