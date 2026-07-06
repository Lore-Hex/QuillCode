import XCTest
@testable import QuillCodeCore

final class RunSpendFusePolicyTests: XCTestCase {
    func testRequestsApprovalWhenPricedThreadSpendCrossesFuse() throws {
        let thread = ChatThread(
            title: "Cost",
            model: "acme/agent",
            events: [
                ModelTokenUsageEvent.event(
                    usage: ModelTokenUsage(promptTokens: 2_000, completionTokens: 1_000),
                    modelID: "acme/agent"
                )
            ]
        )
        let policy = try XCTUnwrap(RunSpendFusePolicy(fuseUSD: 0.01, modelCatalog: [pricedModel()]))

        guard case .request(let request) = policy.approvalState(for: thread) else {
            return XCTFail("Expected spend-fuse approval request.")
        }

        let payload = try JSONHelpers.decode(
            RunSpendFuseApprovalPayload.self,
            from: request.toolCall.argumentsJSON
        )
        XCTAssertEqual(request.scope, .runSpendFuse)
        XCTAssertEqual(request.toolCall.name, RunSpendFusePolicy.toolName)
        XCTAssertEqual(payload.bucket, 1)
        XCTAssertEqual(payload.fuseUSD, 0.01)
        XCTAssertEqual(payload.pricedCallCount, 1)
        XCTAssertEqual(payload.unpricedCallCount, 0)
        XCTAssertEqual(payload.totalUSD, 0.01, accuracy: 0.000_001)
    }

    func testApprovedBucketAllowsTheSameSpendBandButNotTheNextBand() throws {
        let policy = try XCTUnwrap(RunSpendFusePolicy(fuseUSD: 0.01, modelCatalog: [pricedModel()]))
        var thread = ChatThread(
            title: "Cost",
            model: "acme/agent",
            events: [
                ModelTokenUsageEvent.event(
                    usage: ModelTokenUsage(promptTokens: 2_000, completionTokens: 1_000),
                    modelID: "acme/agent"
                )
            ]
        )
        guard case .request(let request) = policy.approvalState(for: thread) else {
            return XCTFail("Expected initial approval request.")
        }
        thread.events.append(ThreadEvent(
            kind: .approvalRequested,
            summary: request.reason,
            payloadJSON: try JSONHelpers.encodePretty(request)
        ))
        thread.events.append(ThreadEvent(
            kind: .approvalDecided,
            summary: "approve: continue",
            payloadJSON: try JSONHelpers.encodePretty(ApprovalDecision(
                requestID: request.id,
                verdict: .approve,
                rationale: "continue"
            ))
        ))

        XCTAssertEqual(policy.approvalState(for: thread), .allowed)

        thread.events.append(ModelTokenUsageEvent.event(
            usage: ModelTokenUsage(promptTokens: 2_000, completionTokens: 1_000),
            modelID: "acme/agent"
        ))
        guard case .request(let nextRequest) = policy.approvalState(for: thread) else {
            return XCTFail("Expected next spend bucket to require a fresh approval.")
        }
        let payload = try JSONHelpers.decode(
            RunSpendFuseApprovalPayload.self,
            from: nextRequest.toolCall.argumentsJSON
        )
        XCTAssertEqual(payload.bucket, 2)
    }

    func testPeriodCapRequestsApprovalWithoutThreadFuse() throws {
        let now = Date(timeIntervalSince1970: 1_735_257_600)
        let thread = ChatThread(title: "Today", model: "acme/agent", events: [
            usageEvent(prompt: 2_000, completion: 1_000, createdAt: now)
        ])
        let policy = try XCTUnwrap(RunSpendFusePolicy(
            fuseUSD: nil,
            periodLimits: RunSpendPeriodLimits(dailyUSD: 0.01),
            periodThreads: [thread],
            modelCatalog: [pricedModel()],
            calendar: utcCalendar(),
            now: now
        ))

        guard case .request(let request) = policy.approvalState(for: thread) else {
            return XCTFail("Expected daily spend-cap approval request.")
        }

        let payload = try JSONHelpers.decode(
            RunSpendFuseApprovalPayload.self,
            from: request.toolCall.argumentsJSON
        )
        XCTAssertEqual(policy.fuseUSD, nil)
        XCTAssertEqual(payload.approvalLimitKind, .daily)
        XCTAssertEqual(payload.fuseUSD, 0.01)
        XCTAssertEqual(payload.totalUSD, 0.01, accuracy: 0.000_001)
        XCTAssertTrue(request.reason.contains("Daily Cap reached $0.01"))
    }

    func testPeriodCapCombinesOtherThreadsAndReplacesActiveThreadSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_735_257_600)
        let activeSnapshot = ChatThread(title: "Active", model: "acme/agent")
        var active = activeSnapshot
        active.events = [usageEvent(prompt: 1_000, completion: 500, createdAt: now)]
        let other = ChatThread(title: "Other", model: "acme/agent", events: [
            usageEvent(prompt: 1_000, completion: 500, createdAt: now)
        ])
        let policy = try XCTUnwrap(RunSpendFusePolicy(
            fuseUSD: nil,
            periodLimits: RunSpendPeriodLimits(dailyUSD: 0.01),
            periodThreads: [activeSnapshot, other],
            modelCatalog: [pricedModel()],
            calendar: utcCalendar(),
            now: now
        ))

        guard case .request(let request) = policy.approvalState(for: active) else {
            return XCTFail("Expected daily cap to include other threads and live active-thread progress.")
        }

        let payload = try JSONHelpers.decode(
            RunSpendFuseApprovalPayload.self,
            from: request.toolCall.argumentsJSON
        )
        XCTAssertEqual(payload.approvalLimitKind, .daily)
        XCTAssertEqual(payload.totalUSD, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(payload.pricedCallCount, 2)
    }

    func testPeriodApprovalDoesNotSatisfyThreadFuseBucket() throws {
        let now = Date(timeIntervalSince1970: 1_735_257_600)
        let policy = try XCTUnwrap(RunSpendFusePolicy(
            fuseUSD: 0.01,
            periodLimits: RunSpendPeriodLimits(dailyUSD: 0.01),
            modelCatalog: [pricedModel()],
            calendar: utcCalendar(),
            now: now
        ))
        var thread = ChatThread(title: "Cost", model: "acme/agent", events: [
            usageEvent(prompt: 2_000, completion: 1_000, createdAt: now)
        ])
        let dailyPayload = RunSpendFuseApprovalPayload(
            totalUSD: 0.01,
            fuseUSD: 0.01,
            bucket: 1,
            pricedCallCount: 1,
            unpricedCallCount: 0,
            limitKind: .daily
        )
        let request = ApprovalRequest(
            id: "approval-daily",
            scope: .runSpendFuse,
            toolCall: ToolCall(
                name: RunSpendFusePolicy.toolName,
                argumentsJSON: try JSONHelpers.encodePretty(dailyPayload)
            ),
            toolDefinition: nil,
            reason: "daily"
        )
        thread.events.append(ThreadEvent(
            kind: .approvalRequested,
            summary: request.reason,
            payloadJSON: try JSONHelpers.encodePretty(request)
        ))
        thread.events.append(ThreadEvent(
            kind: .approvalDecided,
            summary: "approve daily",
            payloadJSON: try JSONHelpers.encodePretty(ApprovalDecision(
                requestID: request.id,
                verdict: .approve,
                rationale: "daily only"
            ))
        ))

        guard case .request(let nextRequest) = policy.approvalState(for: thread) else {
            return XCTFail("Expected thread-fuse request to remain distinct from daily approval.")
        }
        let payload = try JSONHelpers.decode(
            RunSpendFuseApprovalPayload.self,
            from: nextRequest.toolCall.argumentsJSON
        )
        XCTAssertEqual(payload.approvalLimitKind, .threadFuse)
    }

    func testLegacyToolApprovalRequestsDecodeAsToolScope() throws {
        let request = ApprovalRequest(
            id: "approval-legacy",
            toolCall: ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"whoami"}"#),
            toolDefinition: nil,
            reason: "review"
        )
        var object = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]
        object?.removeValue(forKey: "scope")
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(object))

        let decoded = try JSONDecoder().decode(ApprovalRequest.self, from: data)

        XCTAssertEqual(decoded.scope, .tool)
    }

    private func pricedModel() -> ModelInfo {
        ModelInfo(
            id: "acme/agent",
            provider: "acme",
            displayName: "Acme Agent",
            category: "Custom",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: 2.0,
                outputPricePerMillionTokens: 6.0
            )
        )
    }

    private func usageEvent(prompt: Int, completion: Int, createdAt: Date) -> ThreadEvent {
        var event = ModelTokenUsageEvent.event(
            usage: ModelTokenUsage(promptTokens: prompt, completionTokens: completion),
            modelID: "acme/agent"
        )
        event.createdAt = createdAt
        return event
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
