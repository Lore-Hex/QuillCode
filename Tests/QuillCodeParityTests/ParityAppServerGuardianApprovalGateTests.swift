import XCTest

final class ParityAppServerGuardianApprovalGateTests: QuillCodeParityTestCase {
    func testGuardianApprovalStaysWiredThroughRuntimePersistenceTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let review = try text(root, "Sources/QuillCodeCLI/AppServerGuardianReview.swift")
        let projector = try text(
            root,
            "Sources/QuillCodeCLI/AppServerProgressProjector.swift"
        )
        let tests = try text(root, "Tests/QuillCodeCLITests/AppServerSessionTests.swift")
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(session, containsAll: [
            "case \"thread/approveGuardianDeniedAction\"",
            "activeGuardianRetries",
            "launchGuardianRetry"
        ])
        Self.assertSource(review, containsAll: [
            "retryAutoReviewDenial",
            "event.turnID == identity.turnID",
            "event.targetItemID == denial.request.toolCall.id",
            "event.action.matches",
            "retryState == .available",
            "repository.save"
        ])
        Self.assertSource(projector, containsAll: [
            "item/autoApprovalReview/started",
            "item/autoApprovalReview/completed",
            "guardianReviewStarted"
        ])
        Self.assertSource(
            tests,
            contains: "testGuardianDenialApprovalValidatesRetriesPersistsAndRejectsReplay"
        )
        Self.assertSource(smoke, containsAll: [
            "thread/approveGuardianDeniedAction",
            "Guardian denial is no longer available"
        ])
        Self.assertSource(parity, contains: "App-server Guardian denial approval")
        Self.assertSource(research, contains: "thread/approveGuardianDeniedAction")
        Self.assertSource(decisions, contains: "Guardian denial approval reuses durable Auto review")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
