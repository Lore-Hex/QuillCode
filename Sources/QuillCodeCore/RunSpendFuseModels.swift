import Foundation

public enum RunSpendFuseApprovalState: Sendable, Hashable {
    case allowed
    case blocked(existingRequestID: String)
    case request(ApprovalRequest)
}

public enum RunSpendLimitKind: String, Codable, Sendable, Hashable {
    case threadFuse = "thread_fuse"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    public var label: String {
        switch self {
        case .threadFuse: return "thread fuse"
        case .daily: return "daily cap"
        case .weekly: return "weekly cap"
        case .monthly: return "monthly cap"
        }
    }
}

public struct RunSpendFuseApprovalPayload: Codable, Sendable, Hashable {
    public var totalUSD: Double
    public var fuseUSD: Double
    public var bucket: Int
    public var pricedCallCount: Int
    public var unpricedCallCount: Int
    public var limitKind: RunSpendLimitKind?

    public init(
        totalUSD: Double,
        fuseUSD: Double,
        bucket: Int,
        pricedCallCount: Int,
        unpricedCallCount: Int,
        limitKind: RunSpendLimitKind? = nil
    ) {
        self.totalUSD = max(0, totalUSD)
        self.fuseUSD = max(0, fuseUSD)
        self.bucket = max(1, bucket)
        self.pricedCallCount = max(0, pricedCallCount)
        self.unpricedCallCount = max(0, unpricedCallCount)
        self.limitKind = limitKind
    }

    public var approvalLimitKind: RunSpendLimitKind {
        limitKind ?? .threadFuse
    }
}

public struct RunSpendFuseSummary: Sendable, Hashable {
    public var totalUSD: Double
    public var pricedCallCount: Int
    public var unpricedCallCount: Int

    public init(totalUSD: Double = 0, pricedCallCount: Int = 0, unpricedCallCount: Int = 0) {
        self.totalUSD = max(0, totalUSD)
        self.pricedCallCount = max(0, pricedCallCount)
        self.unpricedCallCount = max(0, unpricedCallCount)
    }
}
