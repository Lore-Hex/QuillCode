import QuillCodeCore

enum WorkspaceActivityHandoffSummaryBuilder {
    static func summary(
        for thread: ChatThread,
        latestRequestTitle: String,
        toolCards: [ToolCardState],
        sources: [ActivityItemSurface],
        artifacts: [ToolArtifactState],
        finalAnswer: String?,
        agentStatus: String
    ) -> String {
        let toolNames = toolCards.suffix(4).map {
            WorkspaceToolDisplayNameBuilder.displayName(for: $0.title)
        }
        let artifactLabels = artifacts.suffix(4).map(\.label)
        var lines = [
            "Thread: \(WorkspaceActivityText.boundedLine(thread.title, limit: 80))",
            "Latest request: \(latestRequestTitle)",
            "Status: \(agentStatus)",
            "Tools: \(WorkspaceActivityText.summary(count: toolCards.count, singular: "tool", details: toolNames))",
            "Sources: \(WorkspaceActivityText.countLabel(sources.count, singular: "source"))",
            "Artifacts: \(WorkspaceActivityText.summary(count: artifacts.count, singular: "artifact", details: artifactLabels))"
        ]
        if let finalAnswer {
            lines.append("Latest answer: \(WorkspaceActivityText.boundedLine(finalAnswer, limit: 160))")
        }
        return lines.joined(separator: "\n")
    }
}
