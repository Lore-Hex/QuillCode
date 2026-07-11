import QuillCodeCore

struct WorkspaceContextBannerBuilder: Sendable, Hashable {
    static let defaultTokenBudget = 32_000
    static let defaultWarningThresholdPercent = 80

    var thread: ChatThread?
    var tokenBudget: Int = Self.defaultTokenBudget
    var warningThresholdPercent: Int = Self.defaultWarningThresholdPercent

    func banner() -> ContextBannerSurface? {
        guard let thread, !thread.messages.isEmpty else { return nil }
        let usedPercent = contextUsedPercent(for: thread)
        guard usedPercent >= effectiveWarningThresholdPercent else { return nil }
        let hasProviderUsage = Self.latestProviderUsage(for: thread) != nil
        let progress = Self.contextSummaryProgress(for: thread)
        let contextCommandIsEnabled = progress == nil

        return ContextBannerSurface(
            usedPercent: usedPercent,
            title: "\(usedPercent >= 100 ? "Context limit reached" : "Approaching context limit") (\(usedPercent)% used)",
            subtitle: hasProviderUsage
                ? "Provider-reported token usage is near the limit. Compact the thread, start fresh, or fork with latest, summarized, or full visible context."
                : "Older turns may drop out soon. Compact the thread, start fresh, or fork with latest, summarized, or full visible context.",
            progress: progress,
            newThreadCommand: WorkspaceCommandSurface(id: "new-chat", title: "New thread"),
            forkCommand: WorkspaceThreadForkStrategy.latestTurn.command(isEnabled: contextCommandIsEnabled),
            forkCommands: WorkspaceThreadForkStrategy.allCases.map { $0.command(isEnabled: contextCommandIsEnabled) },
            compactCommand: WorkspaceCommandSurface(
                id: "compact-context",
                title: progress?.activeCommandID == "compact-context" ? "Compacting..." : "Compact context",
                isEnabled: contextCommandIsEnabled
            )
        )
    }

    func contextUsedPercent(for thread: ChatThread) -> Int {
        let tokens = max(1, Self.latestProviderUsage(for: thread)?.contextTokens ?? Self.estimatedContextTokens(for: thread))
        return min(100, Int((Double(tokens) / Double(effectiveTokenBudget) * 100).rounded()))
    }

    static func estimatedContextTokens(for thread: ChatThread) -> Int {
        let messageCharacters = thread.messages.reduce(0) { total, message in
            total + message.content.count + 24 + (message.attachments.count * 4_096)
        }
        let eventCharacters = thread.events.reduce(0) { total, event in
            total + event.summary.count + (event.payloadJSON?.count ?? 0)
        }
        let instructionCharacters = thread.instructions.reduce(0) { total, instruction in
            total + instruction.content.count
        }
        return (messageCharacters + eventCharacters + instructionCharacters) / 4
    }

    static func latestProviderUsage(for thread: ChatThread) -> ModelTokenUsage? {
        thread.events.reversed().compactMap(ModelTokenUsageEvent.usage(from:)).first
    }

    static func contextSummaryProgress(for thread: ChatThread) -> ContextBannerProgressSurface? {
        for event in thread.events.reversed() where event.kind == .notice {
            switch event.summary {
            case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact):
                return ContextBannerProgressSurface(
                    activeCommandID: "compact-context",
                    title: "Compacting context",
                    detail: "Preparing a durable continuation summary before starting the compacted thread."
                )
            case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary):
                return ContextBannerProgressSurface(
                    activeCommandID: WorkspaceThreadForkStrategy.summarizedContext.commandID,
                    title: "Summarizing fork",
                    detail: "Preparing a fork-ready context summary before opening the new thread."
                )
            case WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: "", source: .model),
                purpose: .compact
            ),
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: "", source: .model),
                purpose: .forkSummary
            ),
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: nil, source: .deterministicFallback),
                purpose: .compact
            ),
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: nil, source: .deterministicFallback),
                purpose: .forkSummary
            ):
                return nil
            default:
                continue
            }
        }
        return nil
    }

    private var effectiveTokenBudget: Int {
        max(1, tokenBudget)
    }

    private var effectiveWarningThresholdPercent: Int {
        min(100, max(0, warningThresholdPercent))
    }
}
