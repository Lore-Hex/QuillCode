import Foundation

public struct ModelProviderHealthRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String { provider }
    public var provider: String
    public var statusLabel: String
    public var statusTone: String
    public var modelCount: Int
    public var statusBreakdown: [String]

    public init(
        provider: String,
        statusLabel: String,
        statusTone: String,
        modelCount: Int,
        statusBreakdown: [String]
    ) {
        self.provider = provider
        self.statusLabel = statusLabel
        self.statusTone = statusTone
        self.modelCount = max(0, modelCount)
        self.statusBreakdown = statusBreakdown
    }
}

public struct ModelProviderHealthSummary: Codable, Sendable, Hashable {
    public var label: String
    public var detail: String
    public var rows: [ModelProviderHealthRow]

    public init(label: String, detail: String, rows: [ModelProviderHealthRow]) {
        self.label = label
        self.detail = detail
        self.rows = rows
    }

    public static func summarize(_ models: [ModelInfo]) -> ModelProviderHealthSummary {
        let buckets = providerBuckets(from: models)
        let rows = buckets
            .map(providerHealthRow)
            .sorted(by: sortRows)
        return ModelProviderHealthSummary(
            label: label(for: rows),
            detail: detail(for: rows),
            rows: rows
        )
    }

    private static func providerBuckets(from models: [ModelInfo]) -> [ProviderStatusBucket] {
        var buckets: [String: ProviderStatusBucket] = [:]
        for model in models {
            guard let status = normalizedStatus(model.capabilities.status) else { continue }
            let provider = TrustedRouterDefaults.canonicalProvider(model.provider)
            buckets[provider, default: ProviderStatusBucket(provider: provider)].record(status)
        }
        return Array(buckets.values)
    }

    private static func providerHealthRow(_ bucket: ProviderStatusBucket) -> ModelProviderHealthRow {
        let status = bucket.representativeStatus()
        return ModelProviderHealthRow(
            provider: bucket.provider,
            statusLabel: status.label,
            statusTone: status.tone.rawValue,
            modelCount: bucket.modelCount,
            statusBreakdown: bucket.statusBreakdown()
        )
    }

    private static func label(for rows: [ModelProviderHealthRow]) -> String {
        guard !rows.isEmpty else { return "Provider health unavailable" }
        let attentionCount = rows.filter { isAttentionTone($0.statusTone) }.count
        if attentionCount > 0 {
            let verb = attentionCount == 1 ? "needs" : "need"
            return "Provider health: \(attentionCount) \(plural("provider", attentionCount)) \(verb) attention"
        }
        if rows.contains(where: { $0.statusTone == StatusTone.reported.rawValue }) {
            return "Provider health: \(rows.count) \(plural("provider", rows.count)) reporting"
        }
        return "Provider health: all clear"
    }

    private static func detail(for rows: [ModelProviderHealthRow]) -> String {
        guard !rows.isEmpty else {
            return "TrustedRouter catalog did not include live provider status metadata."
        }
        let modelCount = rows.reduce(0) { $0 + $1.modelCount }
        let rollup = rows.prefix(4).map { row in
            "\(row.provider): \(row.statusBreakdown.joined(separator: ", "))"
        }.joined(separator: "; ")
        let prefix: String
        if rows.contains(where: { isAttentionTone($0.statusTone) }) {
            prefix = "Provider statuses needing attention"
        } else {
            let providerCount = "\(rows.count) \(plural("provider", rows.count))"
            let reportingModelCount = "\(modelCount) \(plural("model", modelCount))"
            prefix = "\(providerCount) / \(reportingModelCount) report status"
        }
        return "\(prefix): \(rollup)."
    }

    private static func sortRows(_ lhs: ModelProviderHealthRow, _ rhs: ModelProviderHealthRow) -> Bool {
        let lhsTone = StatusTone(rawValue: lhs.statusTone) ?? .reported
        let rhsTone = StatusTone(rawValue: rhs.statusTone) ?? .reported
        if lhsTone != rhsTone {
            return lhsTone.rank > rhsTone.rank
        }
        return lhs.provider < rhs.provider
    }

    private static func normalizedStatus(_ value: String?) -> String? {
        let words = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() } ?? []
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func isAttentionTone(_ tone: String) -> Bool {
        tone == StatusTone.warning.rawValue || tone == StatusTone.critical.rawValue
    }

    private static func plural(_ noun: String, _ count: Int) -> String {
        count == 1 ? noun : "\(noun)s"
    }
}

private struct ProviderStatusBucket {
    var provider: String
    var statuses: [String: Int] = [:]
    var modelCount = 0

    mutating func record(_ status: String) {
        modelCount += 1
        statuses[status, default: 0] += 1
    }

    func representativeStatus() -> ProviderStatus {
        statuses
            .map { ProviderStatus(label: $0.key, count: $0.value) }
            .sorted(by: ProviderStatus.sort)
            .first ?? ProviderStatus(label: "unknown", count: 0)
    }

    func statusBreakdown() -> [String] {
        statuses
            .map { ProviderStatus(label: $0.key, count: $0.value) }
            .sorted(by: ProviderStatus.sort)
            .map { status in
                "\(status.label) (\(status.count) \(status.count == 1 ? "model" : "models"))"
            }
    }
}

private struct ProviderStatus: Hashable {
    var label: String
    var count: Int

    var tone: StatusTone {
        StatusTone.classify(label)
    }

    static func sort(_ lhs: ProviderStatus, _ rhs: ProviderStatus) -> Bool {
        if lhs.tone != rhs.tone { return lhs.tone.rank > rhs.tone.rank }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.label < rhs.label
    }
}

private enum StatusTone: String, Codable, Sendable, Hashable {
    case healthy
    case reported
    case warning
    case critical

    var rank: Int {
        switch self {
        case .healthy:
            return 0
        case .reported:
            return 1
        case .warning:
            return 2
        case .critical:
            return 3
        }
    }

    static func classify(_ status: String) -> StatusTone {
        if healthyStatuses.contains(status) { return .healthy }
        if warningStatuses.contains(status) { return .warning }
        if criticalStatuses.contains(status) { return .critical }
        return .reported
    }

    private static let healthyStatuses: Set<String> = [
        "available",
        "healthy",
        "ok",
        "online",
        "operational",
        "ready"
    ]

    private static let warningStatuses: Set<String> = [
        "degraded",
        "limited",
        "maintenance",
        "overloaded",
        "rate limited",
        "slow",
        "warmup",
        "warming"
    ]

    private static let criticalStatuses: Set<String> = [
        "disabled",
        "down",
        "error",
        "failed",
        "offline",
        "unavailable"
    ]
}
