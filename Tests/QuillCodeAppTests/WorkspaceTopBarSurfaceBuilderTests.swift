import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceTopBarSurfaceBuilderTests: XCTestCase {
    private func makeTempDirectory(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("topbar-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testBuildsThreadTopBarWithSourcesRuntimeIssueAndComputerUseState() {
        let thread = ChatThread(title: "Ship QuillCode", model: TrustedRouterDefaults.prometheusModel)
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "AGENTS.md",
                content: "Use Swift idioms.",
                byteCount: 17
            )
        ]
        let memories = [
            MemoryNote(
                id: "global",
                scope: .global,
                title: "Preference",
                content: "Prefer small PRs.",
                relativePath: "memories/preference.md",
                byteCount: 17
            )
        ]
        let runtimeIssue = RuntimeIssueSurface(
            severity: .warning,
            title: "Rate limited",
            message: "TrustedRouter is retrying."
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(
                appName: "QuillCode",
                projectName: "QuillCode",
                model: TrustedRouterDefaults.prometheusModel,
                mode: .review,
                agentStatus: TopBarAgentStatusLabel.streaming,
                computerUseStatus: .permissionStatus(
                    screenRecordingGranted: true,
                    accessibilityGranted: false
                )
            ),
            thread: thread,
            projectName: "QuillCode",
            instructions: instructions,
            memories: memories,
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([
                ModelInfo(
                    id: TrustedRouterDefaults.prometheusModel,
                    provider: TrustedRouterDefaults.trustedRouterProvider,
                    displayName: TrustedRouterDefaults.prometheusModelDisplayName,
                    category: "Recommended",
                    capabilities: ModelCapabilities(status: "available")
                ),
                ModelInfo(
                    id: "acme/code-pro",
                    provider: "acme",
                    displayName: "Code Pro",
                    category: "Coding",
                    capabilities: ModelCapabilities(status: "degraded")
                )
            ]),
            modelCatalogStatus: .liveTrustedRouter(fetchedAt: Date(timeIntervalSinceNow: -30)),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: runtimeIssue
        ).surface()

        XCTAssertEqual(topBar.appName, "QuillCode")
        XCTAssertEqual(topBar.primaryTitle, "Ship QuillCode")
        XCTAssertEqual(topBar.subtitle, "QuillCode - Auto - Prometheus 1.0")
        XCTAssertEqual(topBar.instructionLabel, "1 instruction file loaded")
        XCTAssertEqual(topBar.instructionSources, ["AGENTS.md"])
        XCTAssertEqual(topBar.memoryLabel, "1 memory")
        XCTAssertEqual(topBar.memorySources, ["memories/preference.md"])
        XCTAssertEqual(topBar.modelLabel, TrustedRouterDefaults.prometheusModelDisplayName)
        XCTAssertTrue(topBar.modelCatalogStatusLabel.contains("Live TrustedRouter catalog"))
        XCTAssertTrue(topBar.modelCatalogStatusDetail?.contains("Provider, pricing, modality") == true)
        XCTAssertEqual(topBar.modelProviderHealthLabel, "Provider health: 1 provider needs attention")
        XCTAssertTrue(topBar.modelProviderHealthDetail?.contains("acme: degraded") == true)
        XCTAssertEqual(topBar.selectedModelID, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(topBar.modeLabel, "Review")
        XCTAssertEqual(topBar.agentStatus, TopBarAgentStatusLabel.streaming)
        XCTAssertEqual(topBar.runtimeIssueLabel, "Rate limited")
        XCTAssertEqual(topBar.runtimeIssueSeverity, .warning)
        XCTAssertEqual(topBar.computerUseLabel, "Needs Accessibility")
        XCTAssertTrue(topBar.showsComputerUseSetup)
    }

    func testProjectsTrustedRouterAccountBalanceIntoTopBar() throws {
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 6.5,
            currency: "USD",
            fetchedAt: Date()
        ))
        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel),
            thread: nil,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [],
            runtimeIssue: nil,
            trustedRouterCredits: .current(snapshot),
            hasTrustedRouterCredential: true
        ).surface()

        XCTAssertEqual(topBar.accountBalance?.amountLabel, "$6.50")
        XCTAssertTrue(topBar.topBarAccessibilityLabel.contains("TrustedRouter account balance"))
    }

    func testShowsResolvableWorktreeBindingInTopBar() throws {
        var thread = ChatThread(title: "Feature", model: TrustedRouterDefaults.fastModel)
        let worktree = try makeTempDirectory("worktree")
        thread.worktree = WorktreeBinding(path: worktree.path, branch: "feature/ui", base: "main")

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.worktreeStatusLabel, "Worktree feature/ui")
        XCTAssertEqual(topBar.worktreeStatusIsWarning, false)
        XCTAssertTrue(topBar.worktreeStatusDetail?.contains(worktree.path) == true)
        XCTAssertTrue(topBar.worktreeStatusDetail?.contains("Base: main") == true)
        XCTAssertTrue(topBar.topBarAccessibilityLabel.contains("worktree: Worktree feature/ui"))
    }

    func testCarriesDurablePullRequestStatusInTopBar() {
        var thread = ChatThread(title: "Land task", model: TrustedRouterDefaults.fastModel)
        thread.pullRequest = PullRequestLink(
            number: 42,
            title: "Land task",
            url: "https://github.test/pull/42",
            status: .queued,
            baseBranch: "main",
            headBranch: "feature/land",
            headCommit: "abc123"
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.pullRequest, thread.pullRequest)
        XCTAssertTrue(topBar.topBarAccessibilityLabel.contains("pull request: PR #42 · Queued"))
        XCTAssertTrue(topBar.topBarHelpText.contains("PR #42 · Queued: Land task"))
    }

    func testShowsLocalExecutionWhileRetainingAssociatedWorktree() throws {
        var thread = ChatThread(title: "Managed task", model: TrustedRouterDefaults.fastModel)
        let worktree = try makeTempDirectory("associated-worktree")
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: "",
            base: "main",
            location: .local
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.worktreeStatusLabel, "Local")
        XCTAssertEqual(topBar.worktreeStatusIsWarning, false)
        XCTAssertTrue(topBar.worktreeStatusDetail?.contains("local checkout") == true)
        XCTAssertTrue(topBar.worktreeStatusDetail?.contains(worktree.path) == true)
        XCTAssertTrue(topBar.topBarAccessibilityLabel.contains("worktree: Local"))
    }

    func testShowsDanglingWorktreeBindingAsWarningInTopBar() {
        var thread = ChatThread(title: "Feature", model: TrustedRouterDefaults.fastModel)
        thread.worktree = WorktreeBinding(path: "/tmp/quillcode-missing-\(UUID().uuidString)", branch: "feature/gone")

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.worktreeStatusLabel, "Worktree feature/gone")
        XCTAssertEqual(topBar.worktreeStatusIsWarning, true)
        XCTAssertTrue(topBar.worktreeStatusDetail?.contains("fall back to the project root") == true)
    }

    func testShowsRestorableSnapshotInsteadOfMissingWorktreeWarning() {
        var thread = ChatThread(title: "Archived task", model: TrustedRouterDefaults.fastModel)
        thread.worktree = WorktreeBinding(
            path: "/tmp/quillcode-missing-\(UUID().uuidString)",
            branch: "",
            snapshot: WorktreeSnapshotReference(
                headCommit: String(repeating: "a", count: 40),
                fileCount: 2,
                byteCount: 128
            )
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.worktreeStatusLabel, "Worktree saved")
        XCTAssertFalse(topBar.worktreeStatusIsWarning)
        XCTAssertTrue(topBar.worktreeStatusDetail?.contains("2 local files") == true)
    }

    func testBuildsFallbackTitleAndNoProjectSubtitle() {
        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(),
            thread: nil,
            projectName: nil,
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.primaryTitle, "QuillCode")
        XCTAssertEqual(topBar.subtitle, "No project - Not started")
        XCTAssertEqual(topBar.instructionLabel, "No project instructions")
        XCTAssertEqual(topBar.memoryLabel, "No memories")
        XCTAssertEqual(topBar.computerUseLabel, "Needs Screen Recording + Accessibility")
        XCTAssertTrue(topBar.showsComputerUseSetup)
    }

    func testBuildsLiveWorkSummaryFromActiveToolCards() throws {
        let shellCall = ToolCall(
            id: "shell-1",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"swift test"}"#
        )
        let browserCall = ToolCall(
            id: "browser-1",
            name: ToolDefinition.browserInspect.name,
            argumentsJSON: #"{"url":"http://localhost"}"#
        )
        let thread = ChatThread(
            title: "Run tests",
            model: TrustedRouterDefaults.fastModel,
            events: [
                ThreadEvent(
                    kind: .toolQueued,
                    summary: "host.shell.run queued",
                    payloadJSON: try JSONHelpers.encodePretty(shellCall)
                ),
                ThreadEvent(kind: .toolRunning, summary: "host.shell.run running"),
                ThreadEvent(
                    kind: .toolQueued,
                    summary: "host.browser.inspect queued",
                    payloadJSON: try JSONHelpers.encodePretty(browserCall)
                ),
            ]
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel, agentStatus: TopBarAgentStatusLabel.running),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        let liveWork = try XCTUnwrap(topBar.liveWork)
        XCTAssertEqual(liveWork.label, "2 active tasks")
        XCTAssertEqual(liveWork.tone, .running)
        XCTAssertTrue(liveWork.detail.contains("1 running"))
        XCTAssertTrue(liveWork.detail.contains("1 queued"))
        XCTAssertTrue(liveWork.detail.contains("Focus: Shell command: swift test"))
        XCTAssertTrue(liveWork.detail.contains("Active tools: Shell command, Inspect browser"))
        XCTAssertFalse(liveWork.detail.contains(ToolDefinition.shellRun.name))
        XCTAssertTrue(topBar.topBarAccessibilityLabel.contains("current work: 2 active tasks"))
    }

    func testLiveWorkSummaryUsesReviewToneForApprovalGate() throws {
        let call = ToolCall(
            id: "shell-approval",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"git push"}"#
        )
        let request = ApprovalRequest(
            id: "approval-1",
            toolCall: call,
            toolDefinition: nil,
            reason: "Needs confirmation before pushing.",
            recommendedVerdict: .clarify
        )
        let thread = ChatThread(
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.shell.run queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .approvalRequested, summary: "Review host.shell.run", payloadJSON: try JSONHelpers.encodePretty(request)),
            ]
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(model: TrustedRouterDefaults.fastModel, agentStatus: TopBarAgentStatusLabel.review),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: nil
        ).surface()

        let liveWork = try XCTUnwrap(topBar.liveWork)
        XCTAssertEqual(liveWork.label, "Review Shell command")
        XCTAssertEqual(liveWork.tone, .review)
        XCTAssertTrue(liveWork.detail.contains("1 awaiting review"))
        XCTAssertTrue(liveWork.detail.contains("Focus: Shell command: git push"))
        XCTAssertTrue(topBar.topBarHelpText.contains("Current work:"))
    }

    func testProjectsRateLimitRuntimeIssueIntoTokenQuotaRows() throws {
        let thread = ChatThread(
            title: "Quota",
            model: TrustedRouterDefaults.fastModel,
            events: [
                ModelTokenUsageEvent.event(usage: ModelTokenUsage(promptTokens: 100, completionTokens: 25))
            ]
        )
        let runtimeIssue = RuntimeIssueSurface(
            severity: .warning,
            title: "TrustedRouter rate limit reached",
            message: "Wait for reset or switch models.",
            recovery: RuntimeRecoveryTelemetry(route: .modelPicker, reason: .rateLimited),
            diagnostics: [
                RuntimeDiagnosticSurface(label: "Provider status", value: "Rate limited"),
                RuntimeDiagnosticSurface(label: "Rate limit remaining", value: "0"),
                RuntimeDiagnosticSurface(label: "Rate limit reset", value: "120s"),
            ]
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(
                model: TrustedRouterDefaults.fastModel,
                computerUseStatus: .permissionStatus(
                    screenRecordingGranted: true,
                    accessibilityGranted: true
                )
            ),
            thread: thread,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: [
                ModelInfo(
                    id: TrustedRouterDefaults.fastModel,
                    provider: TrustedRouterDefaults.trustedRouterProvider,
                    displayName: TrustedRouterDefaults.fastModelDisplayName,
                    category: "Recommended",
                    capabilities: ModelCapabilities(contextWindowTokens: 8_000)
                ),
            ],
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentThreads: [thread],
            runtimeIssue: runtimeIssue
        ).surface()

        let budget = try XCTUnwrap(topBar.tokenBudget)
        XCTAssertEqual(budget.visibleQuotaLimits.map(\.compactLabel), ["Quota 0 left", "Reset 2m"])
        XCTAssertEqual(topBar.runtimeIssueLabel, "TrustedRouter rate limit reached")
        XCTAssertTrue(budget.accessibilityLabel.contains("Quota limits: Quota 0 left · Reset 2m"))
    }

    func testBuildsModelCatalogWithFavoritesAndUnarchivedRecents() throws {
        let favoriteModelID = TrustedRouterDefaults.prometheusModel
        let recentModelID = "moonshotai/kimi-k2.6"
        let archivedRecent = ChatThread(
            title: "Archived",
            model: "anthropic/claude-sonnet-4",
            isArchived: true,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let recent = ChatThread(
            title: "Recent",
            model: recentModelID,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let older = ChatThread(
            title: "Older",
            model: favoriteModelID,
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let topBar = WorkspaceTopBarSurfaceBuilder(
            topBarState: TopBarState(
                model: favoriteModelID,
                computerUseStatus: .permissionStatus(
                    screenRecordingGranted: true,
                    accessibilityGranted: true
                )
            ),
            thread: older,
            projectName: "QuillCode",
            instructions: [],
            memories: [],
            modelCatalog: TrustedRouterDefaults.normalizedModelCatalog([
                ModelInfo(
                    id: recentModelID,
                    provider: "moonshotai",
                    displayName: "Kimi K2.6",
                    category: "Safety"
                )
            ]),
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [favoriteModelID],
            recentThreads: [older, recent, archivedRecent],
            runtimeIssue: nil
        ).surface()

        XCTAssertEqual(topBar.computerUseLabel, "Computer Use ready")
        XCTAssertFalse(topBar.showsComputerUseSetup)
        XCTAssertEqual(topBar.modelCategories.prefix(2).map(\.category), ["Favorites", "Recent"])
        XCTAssertEqual(try XCTUnwrap(topBar.modelCategories.first { $0.category == "Favorites" }).models.map(\.id), [favoriteModelID])
        XCTAssertEqual(try XCTUnwrap(topBar.modelCategories.first { $0.category == "Recent" }).models.map(\.id), [recentModelID])
        XCTAssertFalse(topBar.modelCategories.flatMap(\.models).contains { $0.id == archivedRecent.model && $0.badges.contains("Recent") })
    }
}
