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

public struct RunSpendFusePolicy: Sendable, Hashable {
    public static let toolName = "host.run.spend_fuse"

    public var fuseUSD: Double
    public var modelCatalog: [ModelInfo]

    public init?(fuseUSD: Double?, modelCatalog: [ModelInfo]) {
        guard let fuseUSD, fuseUSD.isFinite, fuseUSD > 0 else { return nil }
        self.fuseUSD = fuseUSD
        self.modelCatalog = modelCatalog
    }

    public func approvalState(for thread: ChatThread) -> RunSpendFuseApprovalState {
        let summary = spendSummary(for: thread)
        guard summary.totalUSD + Self.epsilon >= fuseUSD else { return .allowed }

        let bucket = max(1, Int(floor((summary.totalUSD + Self.epsilon) / fuseUSD)))
        guard !hasApprovedBucket(bucket, in: thread) else { return .allowed }
        if let existing = pendingRequestID(for: bucket, in: thread) {
            return .blocked(existingRequestID: existing)
        }
        return .request(approvalRequest(summary: summary, bucket: bucket))
    }

    public func spendSummary(for thread: ChatThread) -> RunSpendFuseSummary {
        thread.events
            .compactMap(ModelTokenUsageEvent.record(from:))
            .reduce(RunSpendFuseSummary()) { summary, record in
                let model = modelInfo(for: record.modelID ?? thread.model)
                guard let price = price(usage: record.usage, model: model) else {
                    return summary.adding(unpricedCalls: 1)
                }
                return summary.adding(totalUSD: price, pricedCalls: 1)
            }
    }

    private func approvalRequest(summary: RunSpendFuseSummary, bucket: Int) -> ApprovalRequest {
        let payload = RunSpendFuseApprovalPayload(
            totalUSD: summary.totalUSD,
            fuseUSD: fuseUSD,
            bucket: bucket,
            pricedCallCount: summary.pricedCallCount,
            unpricedCallCount: summary.unpricedCallCount
        )
        let argumentsJSON = (try? JSONHelpers.encodePretty(payload)) ?? "{}"
        return ApprovalRequest(
            id: "approval-spend-fuse-\(bucket)-\(UUID().uuidString)",
            scope: .runSpendFuse,
            toolCall: ToolCall(
                id: "tool-spend-fuse-\(bucket)-\(UUID().uuidString)",
                name: Self.toolName,
                argumentsJSON: argumentsJSON
            ),
            toolDefinition: nil,
            reason: "Thread spend reached \(Self.costLabel(summary.totalUSD)) against the \(Self.costLabel(fuseUSD)) fuse.",
            recommendedVerdict: .clarify
        )
    }

    private func hasApprovedBucket(_ bucket: Int, in thread: ChatThread) -> Bool {
        let requests = spendFuseRequests(in: thread)
        return thread.events.contains { event in
            guard event.kind == .approvalDecided,
                  let decision = decodeApprovalDecision(event),
                  decision.verdict == .approve,
                  let request = requests[decision.requestID],
                  let payload = spendFusePayload(in: request)
            else {
                return false
            }
            return payload.bucket >= bucket
        }
    }

    private func pendingRequestID(for bucket: Int, in thread: ChatThread) -> String? {
        let decidedIDs = Set(thread.events.compactMap { event -> String? in
            guard event.kind == .approvalDecided,
                  let decision = decodeApprovalDecision(event)
            else {
                return nil
            }
            return decision.requestID
        })
        return thread.events.reversed().compactMap { event -> String? in
            guard event.kind == .approvalRequested,
                  let payloadJSON = event.payloadJSON,
                  let request = try? JSONHelpers.decode(ApprovalRequest.self, from: payloadJSON),
                  request.scope == .runSpendFuse,
                  !decidedIDs.contains(request.id),
                  spendFusePayload(in: request)?.bucket == bucket
            else {
                return nil
            }
            return request.id
        }.first
    }

    private func decodeApprovalDecision(_ event: ThreadEvent) -> ApprovalDecision? {
        guard let payloadJSON = event.payloadJSON else { return nil }
        return try? JSONHelpers.decode(ApprovalDecision.self, from: payloadJSON)
    }

    private func spendFuseRequests(in thread: ChatThread) -> [String: ApprovalRequest] {
        var requests: [String: ApprovalRequest] = [:]
        for event in thread.events {
            guard event.kind == .approvalRequested,
                  let payloadJSON = event.payloadJSON,
                  let request = try? JSONHelpers.decode(ApprovalRequest.self, from: payloadJSON),
                  request.scope == .runSpendFuse
            else {
                continue
            }
            requests[request.id] = request
        }
        return requests
    }

    private func spendFusePayload(in request: ApprovalRequest) -> RunSpendFuseApprovalPayload? {
        try? JSONHelpers.decode(RunSpendFuseApprovalPayload.self, from: request.toolCall.argumentsJSON)
    }

    private func modelInfo(for modelID: String?) -> ModelInfo? {
        let canonical = TrustedRouterDefaults.canonicalModelID(modelID ?? "")
        return modelCatalog.first { TrustedRouterDefaults.canonicalModelID($0.id) == canonical }
    }

    private func price(usage: ModelTokenUsage, model: ModelInfo?) -> Double? {
        guard let inputPrice = model?.capabilities.inputPricePerMillionTokens,
              let outputPrice = model?.capabilities.outputPricePerMillionTokens
        else {
            return nil
        }
        return (Double(usage.promptTokens) * inputPrice + Double(usage.completionTokens) * outputPrice) / 1_000_000
    }

    public static func costLabel(_ value: Double) -> String {
        let safe = max(0, value)
        if safe > 0, safe < 0.01 {
            return String(format: "$%.4f", safe)
        }
        return String(format: "$%.2f", safe)
    }

    private static let epsilon = 0.000_000_001
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
