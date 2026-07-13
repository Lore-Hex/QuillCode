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
        let executionText = try Self.appSourceText(named: "WorkspaceSubagentSchedulerExecution.swift")
        let runnerText = try Self.appSourceText(named: "WorkspaceSubagentSlashCommandRunner.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "WorkspaceModelSlashCommands.swift")
        let slashParserText = try Self.appSourceText(named: "WorkspaceSubagentRunRequest.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let schedulerTests = try Self.appTestSourceText(named: "WorkspaceSubagentSchedulerTests.swift")
        let composerTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")
        let integrationTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandIntegrationTests.swift")
        let modelRunTests = try Self.appTestSourceText(named: "WorkspaceSubagentRunToolIntegrationTests.swift")
        let workerText = try Self.appSourceText(named: "WorkspaceSubagentModelWorker.swift")
        let modelRunText = try Self.appSourceText(named: "WorkspaceSubagentRunToolExecutor.swift")
        let sendFactoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let runContextText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")

        Self.assertSource(schedulerText, containsAll: [
            "ProgressSink",
            "StateSink",
            "func resume("
        ])
        Self.assertSource(executionText, containsAll: [
            "withTaskGroup",
            "catch is CancellationError"
        ])
        Self.assertSource(modelText, contains: "var subagentSchedulerOverride: WorkspaceSubagentScheduler?")
        Self.assertSource(runnerText, containsAll: [
            "AgentWorkspaceSubagentWorker.scheduledWorker",
            "agentSendSessionFactory(",
            "guard !Task.isCancelled",
            "recordSubagentRun",
            "publishSubagentRunSummary"
        ])
        Self.assertSource(workerText, containsAll: [
            "sessionFactory.makeSession",
            "try await session.run(onProgress: onProgress)",
            "threadStore?.save",
            "inheriting: parentThread"
        ])
        Self.assertSource(workerText, excludes: "tools: []")
        Self.assertSource(workerText, contains: "allowsSubagents: false")
        Self.assertSource(modelRunText, containsAll: [
            "struct WorkspaceSubagentRunToolExecutor",
            "WorkspaceSubagentRunToolRequestDecoder.decode",
            "WorkspaceSubagentScheduler(",
            "recordSink?(record, parentThread.id)",
            "await onProgress?(snapshot)"
        ])
        Self.assertSource(sendFactoryText, containsAll: [
            "subagentRunRecordSink",
            "threadToolExecutionOverride",
            "allowsSubagents"
        ])
        Self.assertSource(runContextText, contains: "ToolDefinition.subagentsRun")
        Self.assertSource(slashText, contains: "Task.isCancelled")
        Self.assertSource(slashParserText, contains: "enum SlashSubagentCommandParser")
        Self.assertSource(actionExecutorText, contains: "case .subagents(let request, let userText):")
        Self.assertSource(schedulerTests, containsAll: [
            "testSchedulerRunsWorkersConcurrentlyAndPublishesProgress",
            "testSchedulerMarksCancelledWorkersWithoutTreatingThemAsFailures"
        ])
        Self.assertSource(composerTests, contains: "testCancellingSubagentSlashCommandPublishesCancelledProgressWithoutFinalSummary")
        Self.assertSource(integrationTests, contains: "testSlashSubagentsRunsSchedulerAndRecordsActivityProgress")
        Self.assertSource(modelRunTests, containsAll: [
            "testModelAuthoredDelegationRunsWorkersAndReturnsToParentInOneTurn",
            "testModelAuthoredRunPersistsManifestWhileWorkersAreStillRunning",
            "testToolOutputExposesSummariesWithoutPrivateChildTranscript",
            "testChildSessionCannotStartAnIndependentSubagentTree"
        ])
    }

}
