import Foundation
import QuillCodeCore

struct WorkspaceTopBarSpendStatus: Sendable, Hashable {
    var label: String
    var detail: String
    var spentUSD: Double
    var limitUSD: Double?
}

enum WorkspaceTopBarSpendStatusBuilder {
    static func status(
        thread: ChatThread,
        modelCatalog: [ModelInfo],
        runSpendFuseUSD: Double?
    ) -> WorkspaceTopBarSpendStatus? {
        let ledger = RunSpendLedger(
            thread: thread,
            modelCatalog: modelCatalog,
            fuseUSD: runSpendFuseUSD
        )
        guard !ledger.isEmpty, ledger.pricedCallCount > 0 else { return nil }

        let limitLabel = ledger.fuseUSD.map { " / \(RunSpendLedger.costLabel($0))" } ?? ""
        let unpricedSuffix = ledger.unpricedCallCount > 0 ? " + unpriced" : ""
        let prefix = ledger.fuseUSD == nil ? "Spend " : "Spend limit "
        let label = "\(prefix)\(RunSpendLedger.costLabel(ledger.totalUSD))\(unpricedSuffix)\(limitLabel)"
        let detail = detailText(thread: thread, ledger: ledger)
        return WorkspaceTopBarSpendStatus(
            label: label,
            detail: detail,
            spentUSD: ledger.totalUSD,
            limitUSD: ledger.fuseUSD
        )
    }

    private static func detailText(thread: ChatThread, ledger: RunSpendLedger) -> String {
        var parts = [ledger.summaryDetail]
        if let usage = WorkspaceTokenUsageLabelBuilder.label(
            for: WorkspaceContextBannerBuilder.latestProviderUsage(for: thread)
        ) {
            parts.append("Latest usage: \(usage)")
        }
        if ledger.blocksNextRun {
            parts.append("Spend fuse review required before more model calls")
        }
        return parts.joined(separator: ". ")
    }
}
