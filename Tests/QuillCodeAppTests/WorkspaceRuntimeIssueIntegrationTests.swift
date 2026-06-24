import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceRuntimeIssueIntegrationTests: XCTestCase {
    func testApplyRuntimeRefreshesAgentStatus() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: QuillCodeRuntimeStatusLabel.trustedRouterReady
        ))

        XCTAssertEqual(model.root.topBar.agentStatus, QuillCodeRuntimeStatusLabel.trustedRouterReady)
    }

    func testRuntimeIssueSurfacesMissingTrustedRouterSignIn() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: QuillCodeRuntimeStatusLabel.signInWithTrustedRouter
        ))

        let surface = model.surface()
        XCTAssertEqual(surface.runtimeIssue?.severity, .warning)
        XCTAssertEqual(surface.runtimeIssue?.title, "TrustedRouter sign-in needed")
        XCTAssertEqual(surface.runtimeIssue?.actionLabel, "Open Settings")
        XCTAssertEqual(surface.topBar.runtimeIssueLabel, "TrustedRouter sign-in needed")
        XCTAssertEqual(surface.topBar.runtimeIssueSeverity, .warning)
        XCTAssertEqual(surface.settings.runtimeIssue?.title, "TrustedRouter sign-in needed")
    }

    func testRuntimeIssueNormalizesRejectedTrustedRouterKey() throws {
        let model = QuillCodeWorkspaceModel()

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter OAuth exchange failed with HTTP 401: Invalid API key"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "TrustedRouter key rejected")
        XCTAssertEqual(issue.actionLabel, "Fix key")
        XCTAssertTrue(issue.message.contains("Sign in again"))
    }

    func testRuntimeIssueNormalizesMalformedModelAction() throws {
        let model = QuillCodeWorkspaceModel()

        model.setAgentStatus(
            "Failed",
            lastError: "Expected valid QuillCode action JSON but received an empty argument object."
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Model response was malformed")
        XCTAssertEqual(issue.actionLabel, "Switch model")
    }

    func testRuntimeIssueNormalizesTrustedRouterRateLimit() throws {
        let config = AppConfig(
            defaultModel: TrustedRouterDefaults.synthModel,
            apiBaseURL: "https://api.trustedrouter.test/v1"
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: TrustedRouterDefaults.synthModel),
            trustedRouterAPIKeyConfigured: true
        ))

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter request failed with HTTP 429: Rate limit exceeded. Retry-After: 120. x-ratelimit-remaining: 0"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "TrustedRouter rate limit reached")
        XCTAssertEqual(issue.actionLabel, "Switch model")
        XCTAssertTrue(issue.message.contains("switch models"))

        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["Provider status"], "Rate limited")
        XCTAssertEqual(diagnostics["Retry after"], "120s")
        XCTAssertEqual(diagnostics["Rate limit remaining"], "0")
        XCTAssertEqual(diagnostics["Last error"], "TrustedRouter request failed with HTTP 429: Rate limit exceeded. Retry-After: 120. x-ratelimit-remaining: 0")
    }

    func testRuntimeIssueIncludesRedactedDiagnostics() throws {
        let config = AppConfig(
            defaultModel: "z-ai/glm-5.2",
            apiBaseURL: "https://api.trustedrouter.test/v1",
            developerOverrideEnabled: true
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: "z-ai/glm-5.2"),
            trustedRouterAPIKeyConfigured: true
        ))

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter request timed out with Bearer sk-tr-v1-superSecretDiagnosticKey"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["API base URL"], "https://api.trustedrouter.test/v1")
        XCTAssertEqual(diagnostics["Authentication"], "Developer override")
        XCTAssertEqual(diagnostics["Key state"], "Configured")
        XCTAssertEqual(diagnostics["Model"], "z-ai/glm-5.2")
        XCTAssertEqual(diagnostics["Agent status"], "Failed")
        XCTAssertTrue(diagnostics["Last error"]?.contains("Bearer ...redacted") == true)
        XCTAssertFalse(diagnostics["Last error"]?.contains("superSecretDiagnosticKey") == true)
        XCTAssertEqual(model.surface().settings.runtimeIssue?.diagnostics, issue.diagnostics)
    }

    func testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError() throws {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "run whoami"),
            ChatMessage(role: .assistant, content: "Network failed."),
            ChatMessage(role: .user, content: "run pwd")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.setAgentStatus("Failed", lastError: "Network is unreachable")

        XCTAssertTrue(model.prepareRetryLastUserTurn())

        XCTAssertEqual(model.composer.draft, "run pwd")
        XCTAssertNil(model.lastError)
        XCTAssertNil(model.surface().runtimeIssue)
    }

    func testRetryLastTurnCommandReflectsTranscriptAvailability() throws {
        let emptyModel = QuillCodeWorkspaceModel()
        let emptyRetry = try XCTUnwrap(emptyModel.surface().commands.first { $0.id == "retry-last-turn" })
        XCTAssertFalse(emptyRetry.isEnabled)

        let thread = ChatThread(messages: [
            ChatMessage(role: .assistant, content: "I can help."),
            ChatMessage(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let retry = try XCTUnwrap(model.surface().commands.first { $0.id == "retry-last-turn" })
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(retry.category, WorkspaceCommandPalette.controlCategory)
    }
}
