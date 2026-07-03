import Foundation

public enum RunSpendFuseApprovalState: Sendable, Hashable {
    case allowed
    case blocked(existingRequestID: String)
    case request(ApprovalRequest)
}

public struct RunSpendFuseApprovalPayload: Codable, Sendable, Hashable {
    public var totalUSD: Double
    public var fuseUSD: Double
    public var bucket: Int
    public var pricedCallCount: Int
    public var unpricedCallCount: Int

    public init(
        totalUSD: Double,
        fuseUSD: Double,
        bucket: Int,
        pricedCallCount: Int,
        unpricedCallCount: Int
    ) {
        self.totalUSD = max(0, totalUSD)
        self.fuseUSD = max(0, fuseUSD)
        self.bucket = max(1, bucket)
        self.pricedCallCount = max(0, pricedCallCount)
        self.unpricedCallCount = max(0, unpricedCallCount)
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

    func adding(totalUSD: Double = 0, pricedCalls: Int = 0, unpricedCalls: Int = 0) -> Self {
        Self(
            totalUSD: self.totalUSD + max(0, totalUSD),
            pricedCallCount: pricedCallCount + max(0, pricedCalls),
            unpricedCallCount: unpricedCallCount + max(0, unpricedCalls)
        )
    }
}
