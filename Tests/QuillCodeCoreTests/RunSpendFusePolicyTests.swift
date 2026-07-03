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
}
