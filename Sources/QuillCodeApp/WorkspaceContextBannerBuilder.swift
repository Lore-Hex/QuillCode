import QuillCodeCore

struct WorkspaceContextBannerBuilder: Sendable, Hashable {
    static let defaultTokenBudget = 32_000
    static let defaultWarningThresholdPercent = 80

    var thread: ChatThread?
    var selectedModelID: String = ""
    var modelCatalog: [ModelInfo] = []
    var tokenBudget: Int = Self.defaultTokenBudget
    var warningThresholdPercent: Int = Self.defaultWarningThresholdPercent

    func banner() -> ContextBannerSurface? {
        guard let thread, !thread.messages.isEmpty else { return nil }
        // Provider-reported usage against a model whose window the catalog does not know is not a
        // percentage of anything — the top-bar token chip drops to a usage-only "window unknown"
        // chip in exactly this case (see WorkspaceTokenBudgetSurfaceBuilder). The banner must agree:
        // never fabricate "Context limit reached (100%)" from the 32k estimate fallback here. (The
        // no-provider-usage estimate heuristic below keeps that conservative fallback, as before.)
        let windowTokens = contextWindowTokens()
        if Self.latestProviderUsage(for: thread) != nil, windowTokens == nil { return nil }
        let usedPercent = contextUsedPercent(for: thread, windowTokens: windowTokens)
        guard usedPercent >= effectiveWarningThresholdPercent else { return nil }
        let hasProviderUsage = Self.latestProviderUsage(for: thread) != nil
        let progress = Self.contextSummaryProgress(for: thread)
        let contextCommandIsEnabled = progress == nil
        // Fork and compact mint DURABLE continuations of the transcript — always refused for an
        // ephemeral (incognito) thread. The banner must not present them as live controls that only
        // ever fail; the sole real escape is a fresh chat. (Matches the command-palette gating.)
        let isEphemeral = thread.runtimeContext.isEphemeral
        let durableContinuationEnabled = contextCommandIsEnabled && !isEphemeral

        return ContextBannerSurface(
            usedPercent: usedPercent,
            title: "\(usedPercent >= 100 ? "Context limit reached" : "Approaching context limit") (\(usedPercent)% used)",
            subtitle: isEphemeral
                ? "Older turns may drop out soon. Start a fresh chat to keep going (this private session can't be compacted or forked)."
                : (hasProviderUsage
                    ? "Provider-reported token usage is near the limit. Compact the thread, start fresh, or fork with latest, summarized, or full visible context."
                    : "Older turns may drop out soon. Compact the thread, start fresh, or fork with latest, summarized, or full visible context."),
            progress: progress,
            newThreadCommand: WorkspaceCommandSurface(id: "new-chat", title: "New thread"),
            forkCommand: WorkspaceThreadForkStrategy.latestTurn.command(isEnabled: durableContinuationEnabled),
            forkCommands: WorkspaceThreadForkStrategy.allCases.map { $0.command(isEnabled: durableContinuationEnabled) },
            compactCommand: WorkspaceCommandSurface(
                id: "compact-context",
                title: progress?.activeCommandID == "compact-context" ? "Compacting..." : "Compact context",
                isEnabled: durableContinuationEnabled
            )
        )
    }

    func contextUsedPercent(for thread: ChatThread) -> Int {
        contextUsedPercent(for: thread, windowTokens: contextWindowTokens())
    }

    private func contextUsedPercent(for thread: ChatThread, windowTokens: Int?) -> Int {
        let usage = Self.latestProviderUsage(for: thread)
        let tokens = max(1, usage?.contextTokens ?? Self.estimatedContextTokens(for: thread))
        // Provider-reported usage is a percentage of the model's REAL window when the catalog knows
        // it (so the banner and the top-bar chip agree); the local character estimate — and any
        // unknown-window fallback — uses the injected conservative budget (32k by default).
        let budget = usage == nil ? effectiveTokenBudget : (windowTokens ?? effectiveTokenBudget)
        return min(100, Int((Double(tokens) / Double(budget) * 100).rounded()))
    }

    /// The catalog-reported context window for the thread's model (falling back to the top-bar
    /// selection), or nil when the catalog does not know it — resolved through the SAME helper the
    /// token-budget chip uses, so the chip and the banner can never disagree about the window.
    private func contextWindowTokens() -> Int? {
        WorkspaceTokenBudgetSurfaceBuilder.modelContextWindowTokens(
            threadModel: thread?.model,
            selectedModelID: selectedModelID,
            modelCatalog: modelCatalog
        )
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
            // The local (E2E) start variants share this presentation — the copy here never names a
            // provider, so it stays true whether the summary runs on-device or via the aux model.
            case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact),
                 WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact, isLocal: true):
                return ContextBannerProgressSurface(
                    activeCommandID: "compact-context",
                    title: "Compacting context",
                    detail: "Preparing a durable continuation summary before starting the compacted thread."
                )
            case WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary),
                 WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary, isLocal: true):
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
            ),
            // An E2E-routed summary FINISHES locally. Without these two, the finish notice falls to
            // `default: continue`, the reversed walk reaches the stale START notice, and the banner
            // stays stuck on "Compacting..." forever — disabling compact AND fork (progress != nil)
            // on exactly the oversized E2E threads that need them.
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: nil, source: .e2eDeterministic),
                purpose: .compact
            ),
            WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: WorkspaceContextSummaryOutcome(summaryOverride: nil, source: .e2eDeterministic),
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
