import XCTest

final class ParityWorkspaceAutomationTerminalIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceAutomationIntegrationTestsOwnModelAutomationFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let automationCommandTests = try Self.appTestSourceText(named: "WorkspaceAutomationIntegrationTests.swift")
        let automationSchedulingTests = try Self.appTestSourceText(
            named: "WorkspaceAutomationSchedulingIntegrationTests.swift"
        )
        let automationRunTests = try Self.appTestSourceText(named: "WorkspaceAutomationRunIntegrationTests.swift")
        let automationSupport = try Self.appTestSourceText(named: "WorkspaceAutomationIntegrationTestSupport.swift")

        Self.assertSource(automationCommandTests, containsAll: [
            "testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp",
            "testCreateWorkspaceScheduleCommandPersistsSelectedProjectAutomation"
        ])
        Self.assertSource(automationCommandTests, excludesAll: [
            "testSlashFollowUpSchedulesCurrentThread",
            "testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules"
        ])
        Self.assertSource(automationSchedulingTests, containsAll: [
            "testSlashFollowUpSchedulesCurrentThread",
            "testNaturalLanguageRecurringWorkspaceChecksPersistRecurrence"
        ])
        Self.assertSource(automationRunTests, containsAll: [
            "testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules",
            "testRunDueAutomationsHonorsLimit"
        ])
        Self.assertSource(automationSupport, containsAll: [
            "func makeAutomationWorkspace",
            "func threadFollowUpAutomation"
        ])
        Self.assertSource(modelTests, excludesAll: [
            "testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp",
            "testSlashFollowUpSchedulesCurrentThread",
            "testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules",
            "testRunDueAutomationsHonorsLimit"
        ])
    }

    func testWorkspaceTerminalIntegrationTestsOwnModelTerminalFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let terminalIntegrationTests = try Self.appTestSourceText(named: "WorkspaceTerminalIntegrationTests.swift")

        let terminalFlowTests = [
            "testTerminalCommandRunsInWorkspaceRootAndRecordsOutput",
            "testTerminalCommandStreamsOutputBeforeCompletion",
            "testTerminalCommandPersistsCurrentDirectoryAcrossCommands",
            "testTerminalCommandPersistsEnvironmentAcrossCommands",
            "testTerminalCommandRunsThroughSSHRemoteProject",
            "testTerminalCommandPersistsSSHRemoteCWDAndEnvironment",
            "testTerminalCancellationMarksRunningEntryStopped"
        ]

        Self.assertSource(terminalIntegrationTests, containsAll: terminalFlowTests)
        Self.assertSource(modelTests, excludesAll: terminalFlowTests)
    }
}
