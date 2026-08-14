import XCTest

final class ParityDesktopTaskCoordinationGateTests: QuillCodeParityTestCase {
    func testDesktopControllerDelegatesCancellableTaskSlots() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopControllerSourceText()
        let activeWorkCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopActiveWorkCoordinator.swift")
        let automationCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopAutomationCoordinator.swift")
        let browserCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let composerCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopComposerCoordinator.swift")
        let terminalCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopTerminalCoordinator.swift")
        let terminalControllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController+Terminal.swift")
        let computerUseControllerText = try Self.desktopSourceText(
            named: "QuillCodeDesktopController+ComputerUse.swift"
        )
        let terminalSmokeText = try Self.desktopSourceText(named: "QuillCodeDesktopTerminalRetentionSmoke.swift")
        let smokeRunnerText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeRunner.swift")
        let desktopTaskText = try Self.desktopSourceText(named: "QuillCodeDesktopTaskCoordinator.swift")
        let sharedTaskText = try Self.appSourceText(named: "QuillCodeTaskCoordinator.swift")
        let sharedTaskTests = try Self.appTestSourceText(named: "QuillCodeTaskCoordinatorTests.swift")

        Self.assertSource(text, contains: "QuillCodeDesktopTaskCoordinator")
        Self.assertSource(sharedTaskText, contains: "public final class QuillCodeTaskCoordinator")
        Self.assertSource(desktopTaskText, contains: "QuillCodeTaskCoordinator<Slot>")
        Self.assertSource(sharedTaskText, contains: "guard self?.finish(slot, id: id) == true else { return }")
        Self.assertSource(sharedTaskTests, contains: "testReplaceCancelsStaleTaskAndOnlyFinishesCurrentTask")
        Self.assertSource(controllerText, contains: "QuillCodeDesktopActiveWorkCoordinator")
        Self.assertSource(controllerText, contains: "activeWorkCoordinator.stopAll")
        Self.assertSource(controllerText, contains: "activeWorkCoordinator.disconnectAll")
        Self.assertSource(activeWorkCoordinatorText, contains: "tasks.cancelAllSends()")
        Self.assertSource(activeWorkCoordinatorText, contains: "tasks.cancel([.terminal, .browserPreview, .automationRun])")
        Self.assertSource(activeWorkCoordinatorText, contains: "model.cancelActiveWork()")
        Self.assertSource(activeWorkCoordinatorText, contains: "model.disconnectAll()")
        Self.assertSource(controllerText, contains: "QuillCodeDesktopComposerCoordinator")
        Self.assertSource(controllerText, contains: "composerCoordinator.send")
        Self.assertSource(controllerText, contains: "composerCoordinator.retryLastTurn")
        Self.assertSource(composerCoordinatorText, contains: "tasks.startIfIdle(.send")
        Self.assertSource(composerCoordinatorText, contains: "draft.trimmingCharacters(in: .whitespacesAndNewlines)")
        Self.assertSource(composerCoordinatorText, contains: "model.prepareRetryLastUserTurn()")
        XCTAssertFalse(
            composerCoordinatorText.contains("draft = \"\"\n        refresh()\n        submitPreparedComposer"),
            "Desktop send/retry must not refresh after clearing the visible draft but before submitComposer publishes the optimistic user turn."
        )
        Self.assertSource(controllerText, contains: "QuillCodeDesktopTerminalCoordinator")
        Self.assertSource(controllerText, contains: "terminalCoordinator.runCommand")
        Self.assertSource(controllerText, contains: "terminalCoordinator.recallPreviousCommand")
        Self.assertSource(terminalCoordinatorText, contains: "tasks.startIfIdle(.terminal")
        Self.assertSource(terminalCoordinatorText, contains: "onStateChange: progressRefresh")
        Self.assertSource(terminalControllerText, contains: "self?.scheduleProgressRefresh(.terminal)")
        Self.assertSource(smokeRunnerText, contains: "QuillCodeDesktopTerminalRetentionSmoke.verify")
        Self.assertSource(terminalSmokeText, contains: "entry.stdout.contains(\"output truncated\")")
        Self.assertSource(terminalSmokeText, contains: "outputByteCount < maximumPublishedOutputBytes")
        Self.assertSource(terminalSmokeText, contains: "entry.isRunning")
        Self.assertSource(terminalCoordinatorText, contains: "draft.trimmingCharacters(in: .whitespacesAndNewlines)")
        Self.assertSource(terminalCoordinatorText, contains: "model.setTerminalDraft(draft)")
        Self.assertSource(browserCoordinatorText, contains: "tasks.replace(.browserPreview")
        Self.assertSource(desktopTaskText, containsAll: [
            "case computerUseStatusRefresh",
            "case computerUseForegroundRefresh",
        ])
        Self.assertSource(computerUseControllerText, containsAll: [
            "tasks.replace(.computerUseStatusRefresh)",
            "let changed = await coordinator.refreshStatus",
            "tasks.replace(.computerUseForegroundRefresh)",
            "let changed = await coordinator.refreshForegroundApplication",
        ])
        Self.assertSource(controllerText, contains: "QuillCodeDesktopAutomationCoordinator")
        Self.assertSource(controllerText, contains: "automationCoordinator.startTicker")
        Self.assertSource(automationCoordinatorText, contains: "tasks.replace(.automationTicker")
        Self.assertSource(automationCoordinatorText, contains: "tasks.startIfIdle(.automationRun")
        Self.assertSource(automationCoordinatorText, contains: "Task.sleep(nanoseconds: tickIntervalNanoseconds)")
        Self.assertSource(desktopTaskText, contains: "case automationRun")
        Self.assertSource(desktopTaskText, excludes: "private var tasks")
        Self.assertSource(controllerText, excludes: "private var sendTask")
        Self.assertSource(controllerText, excludes: "private var terminalTask")
        Self.assertSource(controllerText, excludes: "private var browserPreviewTask")
        Self.assertSource(controllerText, excludes: "sendTaskID")
        Self.assertSource(controllerText, excludes: "let prompt = draft.trimmingCharacters")
        Self.assertSource(controllerText, excludes: "model.prepareRetryLastUserTurn()")
        Self.assertSource(controllerText, excludes: "let command = terminalDraft.trimmingCharacters")
        Self.assertSource(controllerText, excludes: "tasks.replace(.automationTicker")
        Self.assertSource(controllerText, excludes: "30_000_000_000")
        Self.assertSource(controllerText, excludes: "tasks.cancel([.send, .terminal, .browserPreview])")
        Self.assertSource(controllerText, excludes: "model.cancelActiveWork()")
        Self.assertSource(controllerText, excludes: "model.disconnectAll()")
    }

    func testDesktopProgressRefreshScopesOwnTheirProjectionBoundaries() throws {
        let refreshText = try Self.desktopSourceText(named: "QuillCodeDesktopController+Refresh.swift")
        let schedulerText = try Self.desktopSourceText(named: "QuillCodeDesktopProgressRefreshScheduler.swift")
        let composerText = try Self.desktopSourceText(named: "QuillCodeDesktopController+ComposerAndPanes.swift")
        let terminalText = try Self.desktopSourceText(named: "QuillCodeDesktopController+Terminal.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let transcriptTrackerText = try Self.appSourceText(
            named: "WorkspaceAgentTranscriptRefreshTracker.swift"
        )

        Self.assertSource(refreshText, contains: "modelStateCoordinator.refreshProgressState(")
        Self.assertSource(refreshText, contains: "progressRefreshScheduler.flush")
        Self.assertSource(refreshText, excludes: "computerUseCoordinator")
        Self.assertSource(schedulerText, contains: "pendingScope.formUnion(scope)")
        Self.assertSource(composerText, contains: "scheduleProgressRefresh(.agent)")
        Self.assertSource(terminalText, contains: "scheduleProgressRefresh(.terminal)")
        Self.assertSource(surfaceText, contains: "func progressSurface(")
        Self.assertSource(surfaceText, contains: "agentTranscriptRefreshTracker.consume(")
        Self.assertSource(surfaceText, contains: "reusing: surface.transcript")
        Self.assertSource(surfaceText, contains: "transcriptRefresh.updatingTranscript")
        Self.assertSource(surfaceText, contains: "next.terminal = terminalSurface()")
        Self.assertSource(transcriptTrackerText, contains: "private var pendingPlan")
        Self.assertSource(transcriptTrackerText, excludes: "[ChatMessage]")
        Self.assertSource(transcriptTrackerText, excludes: "[ThreadEvent]")

        let progressImplementation = try XCTUnwrap(
            surfaceText.components(separatedBy: "func progressSurface(").dropFirst().first
        ).components(separatedBy: "private func agentProgressSurface(").first ?? ""
        XCTAssertFalse(progressImplementation.contains("surface()"))
        XCTAssertFalse(progressImplementation.contains("WorkspaceProjectConfigurationLoader"))

        let agentImplementation = try XCTUnwrap(
            surfaceText.components(separatedBy: "private func agentProgressSurface(").dropFirst().first
        ).components(separatedBy: "private func terminalSurface()").first ?? ""
        XCTAssertFalse(agentImplementation.contains("WorkspaceProjectConfigurationLoader"))
    }

}
