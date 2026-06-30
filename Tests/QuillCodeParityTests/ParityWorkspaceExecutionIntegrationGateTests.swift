import XCTest

final class ParityWorkspaceExecutionIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceComposerIntegrationTestsOwnModelComposerFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let composerIntegrationTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")

        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerRunsToolAndBuildsToolCard"), "Composer tool-card integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerSurfacesToolArtifacts"), "Composer artifact integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerDispatchesComputerUseToolThroughBackend"), "Composer Computer Use integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerStreamsQueuedToolBeforeCompletion"), "Composer queued-tool streaming integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testCancellingComposerRunStopsStateAndRecordsNotice"), "Composer cancellation integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"), "Composer selection-race integration should live in focused composer integration tests.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerRunsToolAndBuildsToolCard"), "WorkspaceModelTests should not own composer tool-card integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerSurfacesToolArtifacts"), "WorkspaceModelTests should not own composer artifact integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerDispatchesComputerUseToolThroughBackend"), "WorkspaceModelTests should not own composer Computer Use integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerStreamsQueuedToolBeforeCompletion"), "WorkspaceModelTests should not own composer queued-tool streaming integration flows.")
        XCTAssertFalse(modelTests.contains("testCancellingComposerRunStopsStateAndRecordsNotice"), "WorkspaceModelTests should not own composer cancellation integration flows.")
        XCTAssertFalse(modelTests.contains("testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"), "WorkspaceModelTests should not own composer selection-race integration flows.")
    }

    func testWorkspaceModelDelegatesSlashCommandDispatchPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandDispatchPlannerTests.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceSlashCommandDispatchAction"), "Slash dispatch actions should be typed values outside WorkspaceModel.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSlashCommandDispatchPlanner"), "Slash dispatch planning should live outside WorkspaceModel.")
        XCTAssertTrue(plannerText.contains("static func action("), "Slash dispatch mapping should be directly testable.")
        XCTAssertTrue(plannerText.contains("case .help:"), "Raw parsed slash-command cases should live in the planner.")
        XCTAssertTrue(plannerText.contains("case .environmentAction(let query):"), "Environment slash routing should live in the planner.")
        XCTAssertTrue(actionExecutorText.contains("extension QuillCodeWorkspaceModel"), "Slash action execution should live in a focused model extension.")
        XCTAssertTrue(actionExecutorText.contains("func runSlashCommandDispatchAction"), "Typed slash action application should live outside the main model file.")
        XCTAssertTrue(actionExecutorText.contains("switch action"), "The slash action executor should own the typed action switch.")
        XCTAssertTrue(composerText.contains("WorkspaceSlashCommandDispatchPlanner.action("), "WorkspaceModel composer APIs should consume the slash dispatch planner.")
        XCTAssertTrue(composerText.contains("await runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)"), "WorkspaceModel composer APIs should delegate typed slash action application.")
        XCTAssertTrue(plannerTests.contains("testExternalCommandFamiliesMapToTypedActions"), "Slash dispatch families should have focused planner coverage.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandDispatchPlanner.action("), "WorkspaceModel.swift should not own slash dispatch planning.")
        XCTAssertFalse(modelText.contains("switch command {\n        case .help:"), "WorkspaceModel should not switch directly over parsed slash commands.")
        XCTAssertFalse(modelText.contains("switch action {"), "WorkspaceModel should not own typed slash action application.")
        XCTAssertFalse(modelText.contains("case .appendTranscript"), "WorkspaceModel should not own typed slash transcript actions.")
        XCTAssertFalse(modelText.contains("case .setMode"), "WorkspaceModel should not own typed slash mode actions.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"), "WorkspaceModel should not own slash workspace-command failure transcripts.")
        XCTAssertFalse(modelText.contains("case .unknown(let name):"), "WorkspaceModel should not own unknown slash-command transcripts.")
        XCTAssertFalse(modelText.contains("case .invalid(let message):"), "WorkspaceModel should not own invalid slash-command transcripts.")
    }

    func testSubagentExecutionIsRealSchedulerNotDisplayOnly() throws {
        let schedulerText = try Self.appSourceText(named: "WorkspaceSubagentScheduler.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceSubagentSlashCommandRunner.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let slashParserText = try Self.appSourceText(named: "WorkspaceSubagentRunRequest.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let schedulerTests = try Self.appTestSourceText(named: "WorkspaceSubagentSchedulerTests.swift")
        let composerTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")
        let integrationTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandIntegrationTests.swift")

        XCTAssertTrue(schedulerText.contains("withTaskGroup"), "Subagent execution should fan out real workers concurrently.")
        XCTAssertTrue(schedulerText.contains("ProgressSink"), "Subagent execution should publish progress while work runs.")
        XCTAssertTrue(schedulerText.contains("catch is CancellationError"), "Subagent cancellation should publish cancelled progress instead of failed progress.")
        XCTAssertTrue(modelText.contains("var subagentScheduler = WorkspaceSubagentScheduler()"), "Workspace model should own an injectable subagent scheduler for cancellation and worker tests.")
        XCTAssertTrue(runnerText.contains("guard !Task.isCancelled"), "Subagent slash runs should not append a final success summary after Stop All cancellation.")
        XCTAssertTrue(composerText.contains("Task.isCancelled"), "Slash-command completion should preserve stopped top-bar state when its task was cancelled.")
        XCTAssertTrue(runnerText.contains("SubagentProgressToolExecutor.execute"), "Subagent runtime progress should reuse the existing tool/event contract.")
        XCTAssertTrue(runnerText.contains("WorkspaceToolEventRecorder.append"), "Subagent progress should be replayable from thread tool events.")
        XCTAssertTrue(slashParserText.contains("enum SlashSubagentCommandParser"), "Subagent slash parsing should live in a focused parser.")
        XCTAssertTrue(actionExecutorText.contains("case .subagents(let request, let userText):"), "Slash dispatch should have a typed subagent execution branch.")
        XCTAssertTrue(schedulerTests.contains("testSchedulerRunsWorkersConcurrentlyAndPublishesProgress"), "Scheduler concurrency needs focused test coverage.")
        XCTAssertTrue(schedulerTests.contains("testSchedulerMarksCancelledWorkersWithoutTreatingThemAsFailures"), "Scheduler cancellation needs focused test coverage.")
        XCTAssertTrue(composerTests.contains("testCancellingSubagentSlashCommandPublishesCancelledProgressWithoutFinalSummary"), "Composer cancellation coverage should prove slash subagents stop without fake success summaries.")
        XCTAssertTrue(integrationTests.contains("testSlashSubagentsRunsSchedulerAndRecordsActivityProgress"), "Slash subagent execution needs workspace integration coverage.")
    }

}
