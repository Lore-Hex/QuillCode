import Foundation

public struct RunSpendFusePolicy: Sendable, Hashable {
    public static let toolName = "host.run.spend_fuse"

    public var fuseUSD: Double?
    public var periodLimits: RunSpendPeriodLimits
    public var periodThreads: [ChatThread]
    public var modelCatalog: [ModelInfo]
    public var calendar: Calendar
    public var now: Date

    public init?(
        fuseUSD: Double?,
        periodLimits: RunSpendPeriodLimits = RunSpendPeriodLimits(),
        periodThreads: [ChatThread] = [],
        modelCatalog: [ModelInfo],
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        let normalizedFuse = RunSpendLedger.normalizedFuse(fuseUSD)
        guard normalizedFuse != nil || periodLimits.hasAnyLimit else { return nil }
        self.fuseUSD = normalizedFuse
        self.periodLimits = periodLimits
        self.periodThreads = periodThreads
        self.modelCatalog = modelCatalog
        self.calendar = calendar
        self.now = now
    }

    public func approvalState(for thread: ChatThread) -> RunSpendFuseApprovalState {
        guard let breach = firstBreach(for: thread) else { return .allowed }

        guard !hasApprovedBucket(breach.bucket, kind: breach.kind, in: thread) else { return .allowed }
        if let existing = pendingRequestID(for: breach.bucket, kind: breach.kind, in: thread) {
            return .blocked(existingRequestID: existing)
        }
        return .request(approvalRequest(breach: breach))
    }

    public func spendSummary(for thread: ChatThread) -> RunSpendFuseSummary {
        RunSpendLedger(
            thread: thread,
            modelCatalog: modelCatalog,
            fuseUSD: fuseUSD
        ).summary
    }

    private func approvalRequest(breach: SpendLimitBreach) -> ApprovalRequest {
        let payload = RunSpendFuseApprovalPayload(
            totalUSD: breach.summary.totalUSD,
            fuseUSD: breach.limitUSD,
            bucket: breach.bucket,
            pricedCallCount: breach.summary.pricedCallCount,
            unpricedCallCount: breach.summary.unpricedCallCount,
            limitKind: breach.kind
        )
        let argumentsJSON = (try? JSONHelpers.encodePretty(payload)) ?? "{}"
        return ApprovalRequest(
            id: "approval-spend-\(breach.kind.rawValue)-\(breach.bucket)-\(UUID().uuidString)",
            scope: .runSpendFuse,
            toolCall: ToolCall(
                id: "tool-spend-\(breach.kind.rawValue)-\(breach.bucket)-\(UUID().uuidString)",
                name: Self.toolName,
                argumentsJSON: argumentsJSON
            ),
            toolDefinition: nil,
            reason: "\(breach.kind.label.capitalized) reached \(Self.costLabel(breach.summary.totalUSD)) "
                + "against the \(Self.costLabel(breach.limitUSD)) local limit.",
            recommendedVerdict: .clarify
        )
    }

    private func hasApprovedBucket(_ bucket: Int, kind: RunSpendLimitKind, in thread: ChatThread) -> Bool {
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
            return payload.approvalLimitKind == kind && payload.bucket >= bucket
        }
    }

    private func pendingRequestID(for bucket: Int, kind: RunSpendLimitKind, in thread: ChatThread) -> String? {
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
                  let payload = spendFusePayload(in: request),
                  payload.approvalLimitKind == kind,
                  payload.bucket == bucket
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

    public static func costLabel(_ value: Double) -> String {
        RunSpendLedger.costLabel(value)
    }

    private func firstBreach(for thread: ChatThread) -> SpendLimitBreach? {
        let threadSummary = spendSummary(for: thread)
        if let fuseUSD,
           let breach = breach(kind: .threadFuse, summary: threadSummary, limitUSD: fuseUSD) {
            return breach
        }
        return periodSpecs.compactMap { spec in
            periodBreach(spec: spec, replacing: thread)
        }.first
    }

    private var periodSpecs: [SpendLimitPeriodSpec] {
        [
            SpendLimitPeriodSpec(kind: .daily, start: calendar.startOfDay(for: now), limitUSD: periodLimits.dailyUSD),
            SpendLimitPeriodSpec(kind: .weekly, start: startOfCurrentWeek(), limitUSD: periodLimits.weeklyUSD),
            SpendLimitPeriodSpec(kind: .monthly, start: startOfCurrentMonth(), limitUSD: periodLimits.monthlyUSD)
        ]
    }

    private func periodBreach(spec: SpendLimitPeriodSpec, replacing thread: ChatThread) -> SpendLimitBreach? {
        guard let limitUSD = spec.limitUSD else { return nil }
        let summary = RunSpendPeriodLedger(
            threads: periodThreads,
            modelCatalog: modelCatalog,
            now: now
        ).summary(since: spec.start, replacing: thread)
        return breach(kind: spec.kind, summary: summary, limitUSD: limitUSD)
    }

    private func breach(
        kind: RunSpendLimitKind,
        summary: RunSpendFuseSummary,
        limitUSD: Double
    ) -> SpendLimitBreach? {
        let epsilon = RunSpendLedger.spendComparisonEpsilon
        guard summary.totalUSD + epsilon >= limitUSD else { return nil }
        let bucket = max(1, Int(floor((summary.totalUSD + epsilon) / limitUSD)))
        return SpendLimitBreach(kind: kind, summary: summary, limitUSD: limitUSD, bucket: bucket)
    }

    private func startOfCurrentWeek() -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    private func startOfCurrentMonth() -> Date {
        calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
    }
}

private struct SpendLimitBreach: Sendable, Hashable {
    var kind: RunSpendLimitKind
    var summary: RunSpendFuseSummary
    var limitUSD: Double
    var bucket: Int
}

private struct SpendLimitPeriodSpec: Sendable, Hashable {
    var kind: RunSpendLimitKind
    var start: Date
    var limitUSD: Double?
}
