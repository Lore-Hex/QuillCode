import XCTest

final class ParityWorkspaceIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceMCPIntegrationTestsOwnModelMCPFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let mcpIntegrationTests = try Self.appTestSourceText(named: "WorkspaceMCPIntegrationTests.swift")

        XCTAssertTrue(mcpIntegrationTests.contains("testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses"), "MCP lifecycle integration should live in a focused test file.")
        XCTAssertTrue(mcpIntegrationTests.contains("testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction"), "Ready MCP surface summaries should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testReadyMCPServerCanBeCalledFromAgentTurn"), "MCP tool-call integration should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testReadyMCPResourceCanBeReadFromAgentTurn"), "MCP resource integration should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testReadyMCPPromptCanBeLoadedFromAgentTurn"), "MCP prompt integration should live in focused MCP tests.")
        XCTAssertTrue(mcpIntegrationTests.contains("testMCPToolCallRejectsUnadvertisedTools"), "MCP safety integration should live in focused MCP tests.")
        XCTAssertFalse(modelTests.contains("testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses"), "WorkspaceModelTests should not own MCP lifecycle integration flows.")
        XCTAssertFalse(modelTests.contains("testReadyMCPServerCanBeCalledFromAgentTurn"), "WorkspaceModelTests should not own MCP tool-call integration flows.")
        XCTAssertFalse(modelTests.contains("testReadyMCPResourceCanBeReadFromAgentTurn"), "WorkspaceModelTests should not own MCP resource integration flows.")
        XCTAssertFalse(modelTests.contains("testReadyMCPPromptCanBeLoadedFromAgentTurn"), "WorkspaceModelTests should not own MCP prompt integration flows.")
        XCTAssertFalse(modelTests.contains("testMCPToolCallRejectsUnadvertisedTools"), "WorkspaceModelTests should not own MCP safety integration flows.")
        XCTAssertFalse(broadSurfaceTests.contains("testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction"), "WorkspaceSurfaceTests should not own ready MCP surface summaries.")
    }

    func testWorkspaceReviewIntegrationTestsOwnModelReviewFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let reviewIntegrationTests = try Self.appTestSourceText(named: "WorkspaceReviewIntegrationTests.swift")

        XCTAssertTrue(reviewIntegrationTests.contains("testApplyPatchToolRunRefreshesReviewDiff"), "Apply-patch diff refresh integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testRunReviewStageActionStagesFileAndRefreshesDiff"), "Local review stage integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff"), "Remote review stage integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testAddReviewCommentAppendsThreadEventForVisibleDiffFile"), "Review comment integration should live in focused review integration tests.")
        XCTAssertTrue(reviewIntegrationTests.contains("testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"), "Review hunk integration should live in focused review integration tests.")
        XCTAssertFalse(modelTests.contains("testApplyPatchToolRunRefreshesReviewDiff"), "WorkspaceModelTests should not own apply-patch review diff refresh integration flows.")
        XCTAssertFalse(modelTests.contains("testRunReviewStageActionStagesFileAndRefreshesDiff"), "WorkspaceModelTests should not own local review stage integration flows.")
        XCTAssertFalse(modelTests.contains("testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff"), "WorkspaceModelTests should not own remote review stage integration flows.")
        XCTAssertFalse(modelTests.contains("testAddReviewCommentAppendsThreadEventForVisibleDiffFile"), "WorkspaceModelTests should not own review comment integration flows.")
        XCTAssertFalse(modelTests.contains("testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"), "WorkspaceModelTests should not own review hunk integration flows.")
    }

    func testFocusedFeedbackAndArtifactTestsOwnSurfaceSpecificFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let feedbackIntegrationTests = try Self.appTestSourceText(named: "WorkspaceFeedbackIntegrationTests.swift")
        let toolCardSurfaceTests = try Self.appTestSourceText(named: "QuillCodeToolCardSurfaceTests.swift")

        XCTAssertTrue(feedbackIntegrationTests.contains("testMessageFeedbackIsStoredAndSurfaced"), "Message feedback persistence and transcript surfacing should live in focused feedback integration tests.")
        XCTAssertTrue(toolCardSurfaceTests.contains("testArtifactStateDerivesLinksAndImagePreviews"), "Image artifact surface derivation should live in focused tool-card surface tests.")
        XCTAssertTrue(toolCardSurfaceTests.contains("testArtifactStateDerivesDocumentPreviews"), "Document artifact surface derivation should live in focused tool-card surface tests.")
        XCTAssertFalse(modelTests.contains("testMessageFeedbackIsStoredAndSurfaced"), "WorkspaceModelTests should not own message feedback integration flows.")
        XCTAssertFalse(modelTests.contains("testArtifactStateDerivesLinksAndImagePreviews"), "WorkspaceModelTests should not own image artifact surface derivation.")
        XCTAssertFalse(modelTests.contains("testArtifactStateDerivesDocumentPreviews"), "WorkspaceModelTests should not own document artifact surface derivation.")
    }

    func testWorkspaceRuntimeIssueIntegrationTestsOwnModelRuntimeIssueFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeIntegrationTests = try Self.appTestSourceText(named: "WorkspaceRuntimeIssueIntegrationTests.swift")

        XCTAssertTrue(runtimeIntegrationTests.contains("testApplyRuntimeRefreshesAgentStatus"), "Runtime status application should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueSurfacesMissingTrustedRouterSignIn"), "Runtime sign-in issue surfacing should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueNormalizesRejectedTrustedRouterKey"), "Runtime key rejection surfacing should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueNormalizesTrustedRouterRateLimit"), "Runtime rate-limit surfacing should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testRuntimeIssueIncludesRedactedDiagnostics"), "Runtime diagnostic redaction should live in focused runtime issue integration tests.")
        XCTAssertTrue(runtimeIntegrationTests.contains("testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"), "Retry recovery mutation should live in focused runtime issue integration tests.")
        XCTAssertFalse(modelTests.contains("testApplyRuntimeRefreshesAgentStatus"), "WorkspaceModelTests should not own runtime status application flows.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueSurfacesMissingTrustedRouterSignIn"), "WorkspaceModelTests should not own runtime sign-in issue surfacing.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueNormalizesRejectedTrustedRouterKey"), "WorkspaceModelTests should not own runtime key rejection surfacing.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueNormalizesTrustedRouterRateLimit"), "WorkspaceModelTests should not own runtime rate-limit surfacing.")
        XCTAssertFalse(modelTests.contains("testRuntimeIssueIncludesRedactedDiagnostics"), "WorkspaceModelTests should not own runtime diagnostic redaction.")
        XCTAssertFalse(modelTests.contains("testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError"), "WorkspaceModelTests should not own retry recovery mutation flows.")
    }

    func testWorkspaceThreadLifecycleIntegrationTestsOwnModelLifecycleFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let lifecycleIntegrationTests = try Self.appTestSourceText(named: "WorkspaceThreadLifecycleIntegrationTests.swift")

        XCTAssertTrue(lifecycleIntegrationTests.contains("testNewChatSelectsThreadAndRefreshesTopBar"), "New chat selection and top-bar integration should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testForkFromLastCreatesBoundedThreadFromLatestUserTurn"), "Fork-from-last integration should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testWorkspaceCommandCompactContextCreatesBoundedThread"), "Compact-context integration should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testPinAndArchiveThreadByIDPersistChanges"), "Thread pin/archive persistence should live in focused thread lifecycle integration tests.")
        XCTAssertTrue(lifecycleIntegrationTests.contains("testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"), "Thread rename/duplicate/unarchive/delete integration should live in focused thread lifecycle integration tests.")
        XCTAssertFalse(modelTests.contains("testNewChatSelectsThreadAndRefreshesTopBar"), "WorkspaceModelTests should not own new-chat lifecycle integration.")
        XCTAssertFalse(modelTests.contains("testForkFromLastCreatesBoundedThreadFromLatestUserTurn"), "WorkspaceModelTests should not own fork-from-last integration.")
        XCTAssertFalse(modelTests.contains("testWorkspaceCommandCompactContextCreatesBoundedThread"), "WorkspaceModelTests should not own compact-context integration.")
        XCTAssertFalse(modelTests.contains("testPinAndArchiveThreadByIDPersistChanges"), "WorkspaceModelTests should not own thread pin/archive persistence integration.")
        XCTAssertFalse(modelTests.contains("testRenameDuplicateUnarchiveAndDeleteThreadLifecycle"), "WorkspaceModelTests should not own thread rename/duplicate/unarchive/delete integration.")
    }

    func testWorkspaceSlashCommandIntegrationTestsOwnCoreSlashFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let slashIntegrationTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandIntegrationTests.swift")

        XCTAssertTrue(slashIntegrationTests.contains("testSlashCommandsRouteToWorkspaceActions"), "Core slash-command dispatch should live in focused slash integration tests.")
        XCTAssertTrue(slashIntegrationTests.contains("testSlashEnvironmentActionListsAndRunsByName"), "Local environment slash integration should live in focused slash integration tests.")
        XCTAssertTrue(slashIntegrationTests.contains("testSlashThreadLifecycleCommands"), "Thread lifecycle slash integration should live in focused slash integration tests.")
        XCTAssertTrue(slashIntegrationTests.contains("testSlashStatusReportsWorkspaceState"), "Slash status integration should live in focused slash integration tests.")
        XCTAssertFalse(modelTests.contains("testSlashCommandsRouteToWorkspaceActions"), "WorkspaceModelTests should not own core slash-command dispatch flows.")
        XCTAssertFalse(modelTests.contains("testSlashEnvironmentActionListsAndRunsByName"), "WorkspaceModelTests should not own local environment slash integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashThreadLifecycleCommands"), "WorkspaceModelTests should not own thread lifecycle slash integration flows.")
        XCTAssertFalse(modelTests.contains("testSlashStatusReportsWorkspaceState"), "WorkspaceModelTests should not own slash status integration flows.")
    }

    func testWorkspaceLocalEnvironmentIntegrationTestsOwnModelLocalEnvironmentFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let localEnvironmentIntegrationTests = try Self.appTestSourceText(named: "WorkspaceLocalEnvironmentIntegrationTests.swift")

        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs"), "Local environment command-palette integration should live in focused local environment tests.")
        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionMetadataInjectsBoundedEnvironment"), "Local environment metadata integration should live in focused local environment tests.")
        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory"), "Local environment working-directory integration should live in focused local environment tests.")
        XCTAssertTrue(localEnvironmentIntegrationTests.contains("testLocalEnvironmentActionMetadataPassesBoundedTimeout"), "Local environment timeout integration should live in focused local environment tests.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs"), "WorkspaceModelTests should not own local environment command-palette integration flows.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionMetadataInjectsBoundedEnvironment"), "WorkspaceModelTests should not own local environment metadata integration flows.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory"), "WorkspaceModelTests should not own local environment working-directory integration flows.")
        XCTAssertFalse(modelTests.contains("testLocalEnvironmentActionMetadataPassesBoundedTimeout"), "WorkspaceModelTests should not own local environment timeout integration flows.")
    }

    func testWorkspaceAutomationIntegrationTestsOwnModelAutomationFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let automationIntegrationTests = try Self.appTestSourceText(named: "WorkspaceAutomationIntegrationTests.swift")

        XCTAssertTrue(automationIntegrationTests.contains("testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp"), "Automation command persistence should live in focused automation integration tests.")
        XCTAssertTrue(automationIntegrationTests.contains("testSlashFollowUpSchedulesCurrentThread"), "Slash follow-up scheduling should live in focused automation integration tests.")
        XCTAssertTrue(automationIntegrationTests.contains("testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules"), "Due automation runs should live in focused automation integration tests.")
        XCTAssertTrue(automationIntegrationTests.contains("testRunDueAutomationsHonorsLimit"), "Due automation limit integration should live in focused automation integration tests.")
        XCTAssertFalse(modelTests.contains("testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp"), "WorkspaceModelTests should not own automation command persistence flows.")
        XCTAssertFalse(modelTests.contains("testSlashFollowUpSchedulesCurrentThread"), "WorkspaceModelTests should not own slash follow-up scheduling flows.")
        XCTAssertFalse(modelTests.contains("testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules"), "WorkspaceModelTests should not own due automation run flows.")
        XCTAssertFalse(modelTests.contains("testRunDueAutomationsHonorsLimit"), "WorkspaceModelTests should not own due automation limit integration flows.")
    }

    func testWorkspaceTerminalIntegrationTestsOwnModelTerminalFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let terminalIntegrationTests = try Self.appTestSourceText(named: "WorkspaceTerminalIntegrationTests.swift")

        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandRunsInWorkspaceRootAndRecordsOutput"), "Local terminal execution integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandStreamsOutputBeforeCompletion"), "Terminal streaming integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandPersistsCurrentDirectoryAcrossCommands"), "Terminal cwd persistence integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandPersistsEnvironmentAcrossCommands"), "Terminal environment persistence integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandRunsThroughSSHRemoteProject"), "SSH Remote terminal execution integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCommandPersistsSSHRemoteCWDAndEnvironment"), "SSH Remote terminal cwd/environment integration should live in focused terminal tests.")
        XCTAssertTrue(terminalIntegrationTests.contains("testTerminalCancellationMarksRunningEntryStopped"), "Terminal cancellation integration should live in focused terminal tests.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandRunsInWorkspaceRootAndRecordsOutput"), "WorkspaceModelTests should not own local terminal execution integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandStreamsOutputBeforeCompletion"), "WorkspaceModelTests should not own terminal streaming integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandPersistsCurrentDirectoryAcrossCommands"), "WorkspaceModelTests should not own terminal cwd persistence integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandPersistsEnvironmentAcrossCommands"), "WorkspaceModelTests should not own terminal environment persistence integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandRunsThroughSSHRemoteProject"), "WorkspaceModelTests should not own SSH Remote terminal execution integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCommandPersistsSSHRemoteCWDAndEnvironment"), "WorkspaceModelTests should not own SSH Remote terminal cwd/environment integration flows.")
        XCTAssertFalse(modelTests.contains("testTerminalCancellationMarksRunningEntryStopped"), "WorkspaceModelTests should not own terminal cancellation integration flows.")
    }

    func testWorkspaceModelTestsDoNotOwnRuntimeFactoryCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeFactoryTests = try Self.appTestSourceText(named: "WorkspaceRuntimeFactoryTests.swift")

        XCTAssertTrue(runtimeFactoryTests.contains("QuillCodeRuntimeFactory("), "Runtime factory coverage should live in its focused test file.")
        XCTAssertTrue(runtimeFactoryTests.contains("fetchModelCatalog"), "Model catalog fallback coverage should stay with runtime factory tests.")
        XCTAssertTrue(runtimeFactoryTests.contains("QUILLCODE_USE_MOCK_LLM"), "Deterministic mock override coverage should stay with runtime factory tests.")
        XCTAssertFalse(modelTests.contains("QuillCodeRuntimeFactory("), "WorkspaceModelTests should focus on model integration, not runtime factory construction.")
        XCTAssertFalse(modelTests.contains("func testRuntimeFactory"), "WorkspaceModelTests should not own runtime factory test cases.")
    }
}
