import Foundation
import QuillCodeCore

struct WorkspaceRunReceiptSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread
    var modelCatalog: [ModelInfo]
    var spendFuseUSD: Double?

    func items() -> [ActivityItemSurface] {
        let receipts = receiptSurfaces()
        guard !receipts.isEmpty else { return [] }
        return [summaryItem(for: receipts)] + receipts.suffix(Self.maxCallReceipts).map(\.item)
    }

    private func receiptSurfaces() -> [RunReceiptSurface] {
        thread.events.compactMap { event in
            guard let record = ModelTokenUsageEvent.record(from: event) else { return nil }
            let model = modelInfo(for: record.modelID ?? thread.model)
            return RunReceiptSurface(
                id: event.id.uuidString,
                usage: record.usage,
                modelID: record.modelID ?? thread.model,
                modelName: model?.displayName,
                price: Self.price(usage: record.usage, model: model)
            )
        }
    }

    private func modelInfo(for modelID: String?) -> ModelInfo? {
        let canonical = TrustedRouterDefaults.canonicalModelID(modelID ?? "")
        return modelCatalog.first { TrustedRouterDefaults.canonicalModelID($0.id) == canonical }
    }

    private func summaryItem(for receipts: [RunReceiptSurface]) -> ActivityItemSurface {
        let pricedTotal = receipts.reduce(0) { $0 + ($1.price?.totalUSD ?? 0) }
        let unpricedCount = receipts.filter { $0.price == nil }.count
        let fuse = Self.normalizedFuse(spendFuseUSD)
        let detail = summaryDetail(
            receipts: receipts,
            pricedTotal: pricedTotal,
            unpricedCount: unpricedCount,
            fuse: fuse
        )
        return ActivityItemSurface(
            id: "run-receipt-total",
            title: "Thread spend",
            detail: detail,
            kind: "run-receipt-summary",
            statusLabel: summaryStatus(pricedTotal: pricedTotal, unpricedCount: unpricedCount, fuse: fuse)
        )
    }

    private func summaryDetail(
        receipts: [RunReceiptSurface],
        pricedTotal: Double,
        unpricedCount: Int,
        fuse: Double?
    ) -> String {
        let totalLabel = unpricedCount == receipts.count ? "Unpriced" : Self.costLabel(pricedTotal)
        var parts = [
            "\(totalLabel) across \(Self.count(receipts.count, singular: "model call"))"
        ]
        if unpricedCount > 0 {
            parts.append("\(unpricedCount) unpriced")
        }
        if let fuse {
            parts.append("fuse \(Self.costLabel(fuse))")
        } else {
            parts.append("fuse off")
        }
        return parts.joined(separator: " · ")
    }

    private func summaryStatus(pricedTotal: Double, unpricedCount: Int, fuse: Double?) -> String {
        if let fuse, pricedTotal >= fuse {
            return "Review"
        }
        if unpricedCount > 0 {
            return "Partial"
        }
        return "Within fuse"
    }

    private static func price(usage: ModelTokenUsage, model: ModelInfo?) -> RunReceiptPrice? {
        guard let inputPrice = model?.capabilities.inputPricePerMillionTokens,
              let outputPrice = model?.capabilities.outputPricePerMillionTokens
        else {
            return nil
        }
        let inputCost = Double(usage.promptTokens) * inputPrice / 1_000_000
        let outputCost = Double(usage.completionTokens) * outputPrice / 1_000_000
        return RunReceiptPrice(inputUSD: inputCost, outputUSD: outputCost)
    }

    private static func normalizedFuse(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    fileprivate static func costLabel(_ value: Double) -> String {
        RunSpendFusePolicy.costLabel(value)
    }

    private static func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }

    private static let maxCallReceipts = 5
}

private struct RunReceiptSurface: Sendable, Hashable {
    var id: String
    var usage: ModelTokenUsage
    var modelID: String
    var modelName: String?
    var price: RunReceiptPrice?

    var item: ActivityItemSurface {
        ActivityItemSurface(
            id: id,
            title: modelName ?? modelID,
            detail: detail,
            kind: "run-receipt",
            statusLabel: price == nil ? "Unpriced" : "Logged"
        )
    }

    private var detail: String {
        [
            modelID,
            WorkspaceTokenUsageLabelBuilder.label(for: usage),
            price?.detailLabel
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct RunReceiptPrice: Sendable, Hashable {
    var inputUSD: Double
    var outputUSD: Double

    var totalUSD: Double {
        inputUSD + outputUSD
    }

    var detailLabel: String {
        let total = WorkspaceRunReceiptSurfaceBuilder.costLabel(totalUSD)
        let input = WorkspaceRunReceiptSurfaceBuilder.costLabel(inputUSD)
        let output = WorkspaceRunReceiptSurfaceBuilder.costLabel(outputUSD)
        return "\(total) (in \(input), out \(output))"
    }
}
