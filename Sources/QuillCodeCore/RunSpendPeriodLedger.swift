import Foundation

public struct RunSpendPeriodLedger: Sendable, Hashable {
    public var threads: [ChatThread]
    public var modelCatalog: [ModelInfo]
    public var now: Date

    public init(
        threads: [ChatThread],
        modelCatalog: [ModelInfo],
        now: Date = Date()
    ) {
        self.threads = threads
        self.modelCatalog = modelCatalog
        self.now = now
    }

    public func spendUSD(since start: Date, replacing replacement: ChatThread? = nil) -> Double {
        summary(since: start, replacing: replacement).totalUSD
    }

    public func summary(since start: Date, replacing replacement: ChatThread? = nil) -> RunSpendFuseSummary {
        threads(replacing: replacement).reduce(RunSpendFuseSummary()) { total, thread in
            let summary = RunSpendLedger(
                thread: periodThread(thread, since: start),
                modelCatalog: modelCatalog,
                fuseUSD: nil
            ).summary
            return RunSpendFuseSummary(
                totalUSD: total.totalUSD + summary.totalUSD,
                pricedCallCount: Self.saturatingAdd(total.pricedCallCount, summary.pricedCallCount),
                unpricedCallCount: Self.saturatingAdd(total.unpricedCallCount, summary.unpricedCallCount)
            )
        }
    }

    private func threads(replacing replacement: ChatThread?) -> [ChatThread] {
        guard let replacement else { return threads }
        var replaced = false
        let updated = threads.map { thread -> ChatThread in
            guard thread.id == replacement.id else { return thread }
            replaced = true
            return replacement
        }
        return replaced ? updated : updated + [replacement]
    }

    private func periodThread(_ thread: ChatThread, since start: Date) -> ChatThread {
        let periodEvents = thread.payloadResidency.deferredSummary?.periodUsage?
            .events(since: start, through: now)
            ?? thread.events.filter { $0.createdAt >= start && $0.createdAt <= now }
        return ChatThread(
            id: thread.id,
            title: thread.title,
            projectID: thread.projectID,
            mode: thread.mode,
            model: thread.model,
            messages: [],
            events: periodEvents,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            instructions: thread.instructions,
            memories: thread.memories,
            composerDraft: thread.composerDraft,
            composerAttachments: thread.composerAttachments,
            followUpQueue: thread.followUpQueue
        )
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}
