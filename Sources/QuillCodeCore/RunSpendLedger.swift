import Foundation

public struct RunSpendLedger: Sendable, Hashable {
    public var receipts: [RunSpendReceipt]
    public var fuseUSD: Double?

    public init(
        thread: ChatThread,
        modelCatalog: [ModelInfo],
        fuseUSD: Double?
    ) {
        let modelIndex = RunSpendLedgerModelIndex(models: modelCatalog)
        self.receipts = thread.events.compactMap { event in
            guard let record = ModelTokenUsageEvent.record(from: event) else { return nil }
            let modelID = record.modelID ?? thread.model
            let model = modelIndex.modelInfo(for: modelID)
            return RunSpendReceipt(
                id: event.id.uuidString,
                usage: record.usage,
                modelID: modelID,
                modelName: model?.displayName,
                price: RunSpendReceiptPrice.price(usage: record.usage, model: model)
            )
        }
        self.fuseUSD = Self.normalizedFuse(fuseUSD)
    }

    public var isEmpty: Bool {
        receipts.isEmpty
    }

    public var totalUSD: Double {
        receipts.reduce(0) { $0 + ($1.price?.totalUSD ?? 0) }
    }

    public var pricedCallCount: Int {
        receipts.count - unpricedCallCount
    }

    public var unpricedCallCount: Int {
        receipts.filter { $0.price == nil }.count
    }

    public var blocksNextRun: Bool {
        guard let fuseUSD else { return false }
        return totalUSD + Self.epsilon >= fuseUSD
    }

    public var summary: RunSpendFuseSummary {
        RunSpendFuseSummary(
            totalUSD: totalUSD,
            pricedCallCount: pricedCallCount,
            unpricedCallCount: unpricedCallCount
        )
    }

    public var summaryStatusLabel: String {
        if blocksNextRun {
            return "Review"
        }
        if unpricedCallCount > 0 {
            return "Partial"
        }
        return "Within fuse"
    }

    public var summaryDetail: String {
        let totalLabel = unpricedCallCount == receipts.count ? "Unpriced" : Self.costLabel(totalUSD)
        var parts = [
            "\(totalLabel) across \(Self.count(receipts.count, singular: "model call"))"
        ]
        if unpricedCallCount > 0 {
            parts.append("\(unpricedCallCount) unpriced")
        }
        if let fuseUSD {
            parts.append("fuse \(Self.costLabel(fuseUSD))")
        } else {
            parts.append("fuse off")
        }
        return parts.joined(separator: " · ")
    }

    public static func normalizedFuse(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    public static func costLabel(_ value: Double) -> String {
        let safe = max(0, value)
        if safe > 0, safe < 0.01 {
            return String(format: "$%.4f", safe)
        }
        return String(format: "$%.2f", safe)
    }

    private static func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }

    private static let epsilon = 0.000_000_001
}

public struct RunSpendReceipt: Sendable, Hashable {
    public var id: String
    public var usage: ModelTokenUsage
    public var modelID: String
    public var modelName: String?
    public var price: RunSpendReceiptPrice?

    public init(
        id: String,
        usage: ModelTokenUsage,
        modelID: String,
        modelName: String?,
        price: RunSpendReceiptPrice?
    ) {
        self.id = id
        self.usage = usage
        self.modelID = modelID
        self.modelName = modelName
        self.price = price
    }
}

public struct RunSpendReceiptPrice: Sendable, Hashable {
    public var inputUSD: Double
    public var outputUSD: Double

    public init(inputUSD: Double, outputUSD: Double) {
        self.inputUSD = max(0, inputUSD)
        self.outputUSD = max(0, outputUSD)
    }

    public var totalUSD: Double {
        inputUSD + outputUSD
    }

    public var detailLabel: String {
        let total = RunSpendLedger.costLabel(totalUSD)
        let input = RunSpendLedger.costLabel(inputUSD)
        let output = RunSpendLedger.costLabel(outputUSD)
        return "\(total) (in \(input), out \(output))"
    }

    static func price(usage: ModelTokenUsage, model: ModelInfo?) -> RunSpendReceiptPrice? {
        guard let inputPrice = model?.capabilities.inputPricePerMillionTokens,
              let outputPrice = model?.capabilities.outputPricePerMillionTokens
        else {
            return nil
        }
        let inputCost = Double(usage.promptTokens) * inputPrice / 1_000_000
        let outputCost = Double(usage.completionTokens) * outputPrice / 1_000_000
        return RunSpendReceiptPrice(inputUSD: inputCost, outputUSD: outputCost)
    }
}

private struct RunSpendLedgerModelIndex: Sendable, Hashable {
    private var modelsByCanonicalID: [String: ModelInfo]

    init(models: [ModelInfo]) {
        var index: [String: ModelInfo] = [:]
        for model in models {
            let canonical = TrustedRouterDefaults.canonicalModelID(model.id)
            index[canonical] = index[canonical] ?? model
        }
        self.modelsByCanonicalID = index
    }

    func modelInfo(for modelID: String?) -> ModelInfo? {
        let canonical = TrustedRouterDefaults.canonicalModelID(modelID ?? "")
        return modelsByCanonicalID[canonical]
    }
}
