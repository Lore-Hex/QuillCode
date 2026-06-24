import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceRuntimeIssueBuilderTests: XCTestCase {
    func testStatusIssueIncludesRuntimeDiagnostics() {
        let issue = WorkspaceRuntimeIssueBuilder(
            config: AppConfig(authMode: .oauth),
            hasStoredAPIKey: false,
            modelID: TrustedRouterDefaults.fastModel,
            agentStatus: QuillCodeRuntimeStatusLabel.signInWithTrustedRouter
        ).surface()

        XCTAssertEqual(issue?.title, "TrustedRouter sign-in needed")
        XCTAssertEqual(issue?.actionLabel, "Open Settings")
        XCTAssertEqual(issue?.diagnostics.map(\.label), [
            "API base URL",
            "Authentication",
            "Key state",
            "Model",
            "Agent status"
        ])
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Authentication" }?.value, "TrustedRouter login")
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Key state" }?.value, "Missing")
    }

    func testDeveloperKeyIssueUsesDeveloperOverrideDiagnostics() {
        let issue = WorkspaceRuntimeIssueBuilder(
            config: AppConfig(authMode: .developerOverride),
            hasStoredAPIKey: false,
            modelID: TrustedRouterDefaults.synthModel,
            agentStatus: QuillCodeRuntimeStatusLabel.developerKeyNeeded
        ).surface()

        XCTAssertEqual(issue?.title, "Developer key needed")
        XCTAssertEqual(issue?.actionLabel, "Add key")
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Authentication" }?.value, "Developer override")
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Model" }?.value, TrustedRouterDefaults.synthModel)
    }

    func testRuntimeStatusLabelsPreserveStableUserFacingCopy() {
        XCTAssertEqual(QuillCodeRuntimeStatusLabel.mockLLM, "Mock LLM")
        XCTAssertEqual(QuillCodeRuntimeStatusLabel.signInWithTrustedRouter, "Sign in with TrustedRouter")
        XCTAssertEqual(QuillCodeRuntimeStatusLabel.developerKeyNeeded, "Developer key needed")
        XCTAssertEqual(QuillCodeRuntimeStatusLabel.trustedRouterSignedIn, "TrustedRouter signed in")
        XCTAssertEqual(QuillCodeRuntimeStatusLabel.trustedRouterReady, "TrustedRouter ready")
        XCTAssertEqual(QuillCodeRuntimeStatusLabel.signInFailed, "Sign-in failed")
    }

    func testRateLimitIssueAddsProviderDiagnosticsAndRedactsSecrets() {
        let issue = WorkspaceRuntimeIssueBuilder(
            config: AppConfig(),
            hasStoredAPIKey: true,
            modelID: "deepseek/deepseek-v4-flash",
            agentStatus: "Failed",
            lastError: "HTTP 429 rate limit. retry-after: 45 x-ratelimit-remaining: 0 sk-testSecret123456 Bearer abcdefghijklmnop"
        ).surface()

        XCTAssertEqual(issue?.title, "TrustedRouter rate limit reached")
        XCTAssertEqual(issue?.actionLabel, "Switch model")
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Provider status" }?.value, "Rate limited")
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Retry after" }?.value, "45s")
        XCTAssertEqual(issue?.diagnostics.first { $0.label == "Rate limit remaining" }?.value, "0")

        let lastError = issue?.diagnostics.first { $0.label == "Last error" }?.value ?? ""
        XCTAssertTrue(lastError.contains("sk-...redacted"))
        XCTAssertTrue(lastError.contains("Bearer ...redacted"))
        XCTAssertFalse(lastError.contains("testSecret123456"))
        XCTAssertFalse(lastError.contains("abcdefghijklmnop"))
    }

    func testNetworkIssueUsesConfiguredBaseURL() {
        let issue = WorkspaceRuntimeIssueBuilder.issue(
            from: "request timed out while connecting",
            config: AppConfig(apiBaseURL: "https://api.example.test/v1")
        )

        XCTAssertEqual(issue?.severity, .error)
        XCTAssertEqual(issue?.title, "TrustedRouter network issue")
        XCTAssertEqual(
            issue?.message,
            "QuillCode could not reach https://api.example.test/v1. Check the network or API base URL, then retry."
        )
    }

    func testMalformedResponseMentionsBrandedFallbackModels() {
        let issue = WorkspaceRuntimeIssueBuilder.issue(
            from: "model returned empty argument object",
            config: AppConfig()
        )

        XCTAssertEqual(issue?.title, "Model response was malformed")
        XCTAssertEqual(issue?.actionLabel, "Switch model")
        XCTAssertTrue(issue?.message.contains(TrustedRouterDefaults.fastModelDisplayName) == true)
        XCTAssertTrue(issue?.message.contains(TrustedRouterDefaults.synthModelDisplayName) == true)
    }
}
