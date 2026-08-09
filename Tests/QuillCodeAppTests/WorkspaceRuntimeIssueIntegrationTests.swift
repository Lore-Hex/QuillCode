import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceRuntimeIssueIntegrationTests: XCTestCase {
    func testSavedChatLoadIssueTakesPriorityAndRoutesToSettings() throws {
        let privateFilename = "customer-acquisition-plan.json"
        let listing = ThreadListing(
            threads: [ChatThread(title: "Healthy")],
            issues: [
                ThreadFileIssue(
                    fileURL: URL(fileURLWithPath: "/ignored/\(privateFilename)"),
                    reason: .exceedsSizeLimit
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                topBar: TopBarState(agentStatus: QuillCodeRuntimeStatusLabel.signInWithTrustedRouter)
            ),
            threadLoadIssue: try XCTUnwrap(WorkspaceThreadLoadIssue(listing: listing))
        )

        let surface = model.surface()

        XCTAssertEqual(surface.runtimeIssue?.title, "A saved chat could not be loaded")
        XCTAssertEqual(surface.runtimeIssue?.recovery?.reason, .savedChatsUnreadable)
        XCTAssertEqual(surface.topBar.runtimeIssueLabel, "A saved chat could not be loaded")
        XCTAssertEqual(
            surface.runtimeIssue?.diagnostics.first { $0.label == "Oversized files" }?.value,
            "1"
        )
        XCTAssertFalse(
            surface.runtimeIssue?.diagnostics.contains { $0.value.contains(privateFilename) } == true
        )
        let settings = try XCTUnwrap(surface.commands.first { $0.id == "settings" })
        XCTAssertEqual(
            RuntimeIssueRecoveryPlanner(commands: [settings]).action(for: surface.runtimeIssue),
            .command(settings)
        )
    }

    func testFailedChatSaveSurfacesContentFreeDurabilityWarning() throws {
        let root = try makeQuillCodeTestDirectory()
        let privateDirectoryName = "acquisition-confidential"
        let blockingFile = root.appendingPathComponent(privateDirectoryName)
        try Data().write(to: blockingFile)
        let thread = ChatThread(title: "Private acquisition plan")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread]),
            threadStore: JSONThreadStore(
                directory: blockingFile.appendingPathComponent("threads")
            )
        )

        model.threadPersistence.save(thread)

        let surface = model.surface()
        let issue = try XCTUnwrap(surface.runtimeIssue)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "A chat change is not saved")
        XCTAssertNil(issue.actionLabel)
        XCTAssertNil(issue.recovery)
        XCTAssertEqual(surface.topBar.runtimeIssueLabel, issue.title)
        XCTAssertEqual(surface.settings.runtimeIssue, issue)
        let visibleText = ([issue.title, issue.message] + issue.diagnostics.flatMap {
            [$0.label, $0.value]
        }).joined(separator: " ")
        XCTAssertFalse(visibleText.contains(privateDirectoryName))
        XCTAssertFalse(visibleText.contains(thread.title))

        try FileManager.default.removeItem(at: blockingFile)
        model.threadPersistence.save(thread)

        XCTAssertNotEqual(model.surface().runtimeIssue?.title, issue.title)
    }

    func testStartupLoadIssueKeepsPriorityOverLaterSaveFailure() throws {
        let root = try makeQuillCodeTestDirectory()
        let blockingFile = root.appendingPathComponent("blocked")
        try Data().write(to: blockingFile)
        let thread = ChatThread(title: "Unsaved")
        let listing = ThreadListing(
            threads: [thread],
            issues: [
                ThreadFileIssue(
                    fileURL: URL(fileURLWithPath: "/ignored/unreadable.json"),
                    reason: .unreadable
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread]),
            threadStore: JSONThreadStore(
                directory: blockingFile.appendingPathComponent("threads")
            ),
            threadLoadIssue: try XCTUnwrap(WorkspaceThreadLoadIssue(listing: listing))
        )

        model.threadPersistence.save(thread)

        XCTAssertEqual(model.threadPersistenceIssueTracker.failedThreadCount, 1)
        XCTAssertEqual(model.surface().runtimeIssue?.title, "A saved chat could not be loaded")
    }

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
            defaultModel: TrustedRouterDefaults.prometheusModel,
            apiBaseURL: "https://api.trustedrouter.test/v1"
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: TrustedRouterDefaults.prometheusModel),
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
