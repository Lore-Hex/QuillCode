import XCTest

final class ParityWorkspaceExecutionIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceComposerIntegrationTestsOwnModelComposerFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let composerIntegrationTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")
        let composerFlowNames = [
            "testSubmitComposerRunsToolAndBuildsToolCard",
            "testSubmitComposerSurfacesToolArtifacts",
            "testSubmitComposerDispatchesComputerUseToolThroughBackend",
            "testSubmitComposerStreamsQueuedToolBeforeCompletion",
            "testCancellingComposerRunStopsStateAndRecordsNotice",
            "testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"
        ]

        Self.assertSource(composerIntegrationTests, containsAll: composerFlowNames)
        Self.assertSource(modelTests, excludesAll: composerFlowNames)
    }

    func testWorkspaceModelDelegatesSlashCommandDispatchPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "WorkspaceModelSlashCommands.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandDispatchPlannerTests.swift")

        Self.assertSource(plannerText, containsAll: [
            "enum WorkspaceSlashCommandDispatchAction",
            "struct WorkspaceSlashCommandDispatchPlanner",
            "static func action(",
            "case .help:",
            "case .environmentAction(let query):",
            "case .environmentSchedule(let scheduleText):"
        ])
        Self.assertSource(actionExecutorText, containsAll: [
            "extension QuillCodeWorkspaceModel",
            "func runSlashCommandDispatchAction",
            "switch action"
        ])
        Self.assertSource(slashText, containsAll: [
            "WorkspaceSlashCommandDispatchPlanner.action(",
            "await runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)"
        ])
        Self.assertSource(plannerTests, contains: "testExternalCommandFamiliesMapToTypedActions")
        Self.assertSource(modelText, excludesAll: [
            "WorkspaceSlashCommandDispatchPlanner.action(",
            "switch command {\n        case .help:",
            "switch action {",
            "case .appendTranscript",
            "case .setMode",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed",
            "case .unknown(let name):",
            "case .invalid(let message):"
        ])
    }

    func testSubagentExecutionIsRealSchedulerNotDisplayOnly() throws {
        let schedulerText = try Self.appSourceText(named: "WorkspaceSubagentScheduler.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceSubagentSlashCommandRunner.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "WorkspaceModelSlashCommands.swift")
        let slashParserText = try Self.appSourceText(named: "WorkspaceSubagentRunRequest.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let schedulerTests = try Self.appTestSourceText(named: "WorkspaceSubagentSchedulerTests.swift")
        let composerTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")
        let integrationTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandIntegrationTests.swift")

        Self.assertSource(schedulerText, containsAll: [
            "withTaskGroup",
            "ProgressSink",
            "catch is CancellationError"
        ])
        Self.assertSource(modelText, contains: "var subagentScheduler = WorkspaceSubagentScheduler()")
        Self.assertSource(runnerText, containsAll: [
            "guard !Task.isCancelled",
            "SubagentProgressToolExecutor.execute",
            "WorkspaceToolEventRecorder.append"
        ])
        Self.assertSource(slashText, contains: "Task.isCancelled")
        Self.assertSource(slashParserText, contains: "enum SlashSubagentCommandParser")
        Self.assertSource(actionExecutorText, contains: "case .subagents(let request, let userText):")
        Self.assertSource(schedulerTests, containsAll: [
            "testSchedulerRunsWorkersConcurrentlyAndPublishesProgress",
            "testSchedulerMarksCancelledWorkersWithoutTreatingThemAsFailures"
        ])
        Self.assertSource(composerTests, contains: "testCancellingSubagentSlashCommandPublishesCancelledProgressWithoutFinalSummary")
        Self.assertSource(integrationTests, contains: "testSlashSubagentsRunsSchedulerAndRecordsActivityProgress")
    }

}
