import Foundation
import QuillCodeCore

struct WorkspaceRunReceiptSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread
    var modelCatalog: [ModelInfo]
    var spendFuseUSD: Double?

    func items() -> [ActivityItemSurface] {
        let ledger = RunSpendLedger(
            thread: thread,
            modelCatalog: modelCatalog,
            fuseUSD: spendFuseUSD
        )
        guard !ledger.isEmpty else { return [] }
        return [summaryItem(for: ledger)] + ledger.receipts.suffix(Self.maxCallReceipts).map(Self.receiptItem)
    }

    private func summaryItem(for ledger: RunSpendLedger) -> ActivityItemSurface {
        ActivityItemSurface(
            id: "run-receipt-total",
            title: "Thread spend",
            detail: ledger.summaryDetail,
            kind: "run-receipt-summary",
            statusLabel: ledger.summaryStatusLabel
        )
    }

    private static func receiptItem(_ receipt: RunSpendReceipt) -> ActivityItemSurface {
        ActivityItemSurface(
            id: receipt.id,
            title: receipt.modelName ?? receipt.modelID,
            detail: receiptDetail(receipt),
            kind: "run-receipt",
            statusLabel: receipt.price == nil ? "Unpriced" : "Logged"
        )
    }

    private static func receiptDetail(_ receipt: RunSpendReceipt) -> String {
        [
            receipt.modelID,
            WorkspaceTokenUsageLabelBuilder.label(for: receipt.usage),
            receipt.price?.detailLabel
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static let maxCallReceipts = 5
}
