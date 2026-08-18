import XCTest

final class ParityDesktopGateTests: QuillCodeParityTestCase {
    func testDesktopDefinesNativeMenuBarWidgetAndUnifiedCommandRouting() throws {
        let text = try Self.desktopSourceText()
        let commandsText = try Self.desktopSourceText(named: "DesktopCommands.swift")
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let rootViewText = try Self.desktopSourceText(named: "QuillCodeDesktopRootView.swift")
        let shortcutMonitorText = try Self.desktopSourceText(
            named: "QuillCodeDesktopShortcutMonitor.swift"
        )

        Self.assertSource(text, contains: "MenuBarExtra")
        Self.assertSource(text, contains: "QuillCodeMenuBarIcon.image")
        let menuIconText = try Self.desktopSourceText(named: "QuillCodeMenuBarIcon.swift")
        Self.assertSource(menuIconText, contains: "QuillCodeMenuBarTemplate")
        Self.assertSource(menuIconText, contains: "isTemplate = true")
        Self.assertSource(menuIconText, contains: "static let image")

        for label in [
            "New Chat",
            "Open Project",
            "Command Palette",
            "Keyboard Shortcuts",
            "Open Browser Session",
            "Computer Use Setup",
            "Settings",
            "Stop All",
            "Disconnect All"
        ] {
            Self.assertSource(text, contains: label)
        }

        for commandID in [
            "new-chat",
            "quick-chat",
            "search",
            "find-in-chat",
            "workspace-back",
            "workspace-forward",
            "previous-task",
            "next-task",
            "toggle-sidebar",
            "git-diff",
            "toggle-review-panel",
            "toggle-bottom-panel",
            "toggle-terminal",
            "terminal-clear",
            "increase-font-size",
            "decrease-font-size",
            "dictation",
            "command-palette",
            "keyboard-shortcuts"
        ] {
            Self.assertSource(commandsText, contains: "id: \"\(commandID)\"")
        }

        Self.assertSource(commandsText, contains: "onCommand(commandID)")
        Self.assertSource(commandsText, excludes: "NotificationCenter.default.post")
        Self.assertSource(commandsText, contains: ".quillCodeShortcut(commandID, profile: shortcutProfile)")
        Self.assertSource(commandsText, contains: ".disabled(commandsByID[commandID]?.isEnabled != true)")
        Self.assertSource(commandsText, contains: "accessibilityIdentifier(\"quillcode-menu-command-\\(commandID)\")")
        Self.assertSource(appText, contains: "onCommand: { controller.runCommand(commandID: $0) }")
        Self.assertSource(rootViewText, contains: "controller.runCommand(commandID: commandID)")
        Self.assertSource(appText, excludes: "observeCommand()")
        Self.assertSource(rootViewText, contains: "QuillCodeSecondaryShortcutResolver.commandID")
        Self.assertSource(
            appText,
            contains: "Window(QuillCodeProduct.displayName, id: QuillCodeDesktopSceneID.mainWindow)"
        )
        Self.assertSource(appText, excludes: "WindowGroup(QuillCodeProduct.displayName)")
        Self.assertSource(shortcutMonitorText, contains: "event.charactersIgnoringModifiers?.first")
        Self.assertSource(shortcutMonitorText, contains: "commandsWithPrimaryBinding")

        let menuText = try Self.desktopSourceText(named: "QuillCodeMenuBarView.swift")
        Self.assertSource(menuText, contains: "onDisconnectAll")
        Self.assertSource(menuText, contains: "onOpenBrowserSession")
        Self.assertSource(menuText, contains: "onReportIssue")
        Self.assertSource(menuText, contains: "@Environment(\\.openWindow) private var openWindow")
        Self.assertSource(menuText, contains: "openWindow(id: QuillCodeDesktopSceneID.mainWindow)")
        Self.assertSource(menuText, contains: "revealsMainWindow: true")
        Self.assertSource(commandsText, contains: "quillcode-menu-report-issue")
        Self.assertSource(appText, contains: "onReportIssue: controller.reportIssue")
        XCTAssertFalse(
            menuText.contains(#"Button("Disconnect All") {}"#),
            "Disconnect All must not regress to a no-op button."
        )
        Self.assertSource(menuText, excludes: ".disabled(true)")
    }

    func testDesktopOwnsUnexpectedExitRecoveryAtTheApplicationBoundary() throws {
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let rootViewText = try Self.desktopSourceText(named: "QuillCodeDesktopRootView.swift")
        let lifecycleText = try Self.desktopSourceText(named: "QuillCodeDesktopLaunchLifecycle.swift")
        let systemApplicationText = try Self.desktopSourceText(
            named: "QuillCodeDesktopSystemApplication.swift"
        )
        let smokeText = try Self.desktopSourceText(named: "QuillCodeDesktopLaunchRecoverySmoke.swift")
        let reporterText = try Self.desktopSourceText(named: "QuillCodeDesktopIssueReporter.swift")

        Self.assertSource(appText, contains: "let unexpectedExit = launchLifecycleController?.startIfNeeded()")
        Self.assertSource(appText, contains: "startupMode: QuillCodeDesktopStartupMode(")
        Self.assertSource(rootViewText, contains: "await Task.yield()")
        Self.assertSource(rootViewText, contains: "controller.completeStartupIfAllowed()")
        Self.assertSource(rootViewText, contains: "controller.resumeAutomaticWorkspaceServices()")
        Self.assertSource(rootViewText, contains: "continueWithAutomaticWorkspaceServicesPaused()")
        Self.assertSource(rootViewText, contains: #""\(QuillCodeProduct.displayName) closed unexpectedly""#)
        Self.assertSource(rootViewText, contains: #""\(QuillCodeProduct.displayName) opened in recovery mode""#)
        Self.assertSource(rootViewText, contains: "controller.launchLifecycleController?.takeUnexpectedExit()")
        Self.assertSource(rootViewText, contains: "QuillCodeDesktopIssueReporter.open(")
        Self.assertSource(lifecycleText, contains: "flock(descriptor, LOCK_EX)")
        Self.assertSource(lifecycleText, contains: "record.launchID == launchID")
        Self.assertSource(lifecycleText, contains: "processIsRunning(record.processIdentifier)")
        Self.assertSource(lifecycleText, contains: "NSApplication.willTerminateNotification")
        Self.assertSource(
            lifecycleText,
            contains: ".quillCodeDesktopWillTerminateForRelaunch"
        )
        Self.assertSource(systemApplicationText, containsAll: [
            "NotificationCenter.default.post(",
            "name: .quillCodeDesktopWillTerminateForRelaunch",
            "Darwin.exit(EXIT_SUCCESS)"
        ])
        Self.assertSource(lifecycleText, contains: "var requiresRecoveryStartup: Bool")
        Self.assertSource(reporterText, contains: "## Previous session")
        Self.assertSource(appText, contains: "QuillCodeDesktopLaunchRecoverySmoke.runAndExit(request)")
        Self.assertSource(smokeText, contains: "try verify(home: root.home)")
    }

    func testDesktopCrashRecoveryCheckpointsLiveComposerDrafts() throws {
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let coordinatorText = try Self.desktopSourceText(
            named: "QuillCodeDesktopComposerDraftCheckpointCoordinator.swift"
        )
        let modelText = try Self.appSourceText(named: "WorkspaceModelComposerDraftPersistence.swift")
        let persistenceText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("Sources/QuillCodePersistence/ComposerDraftCheckpointStore.swift"),
            encoding: .utf8
        )
        let downloadsText = try Self.docsText(named: "DOWNLOADS.md")
        let crashSmokeText = try Self.desktopSourceText(
            named: "QuillCodeDesktopComposerDraftCrashSmoke.swift"
        )
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let packagedSmokeText = try Self.scriptText(named: "packaged-macos-smoke.sh")

        Self.assertSource(controllerText, contains: "composerDraftCheckpointCoordinator.schedule")
        Self.assertSource(controllerText, contains: "model.updateLiveComposerDraft")
        Self.assertSource(controllerText, contains: "isComposerDraftBindingSideEffectsSuppressed")
        let composerActionsText = try Self.desktopSourceText(
            named: "QuillCodeDesktopController+ComposerAndPanes.swift"
        )
        Self.assertSource(composerActionsText, contains: "composerDraftCheckpointCoordinator.flush")
        Self.assertSource(
            composerActionsText,
            contains: "isComposerDraftBindingSideEffectsSuppressed = true"
        )
        Self.assertSource(coordinatorText, contains: "defaultDelayNanoseconds: UInt64 = 350_000_000")
        Self.assertSource(coordinatorText, contains: "ownerThreadID: model.selectedThread?.id")
        Self.assertSource(coordinatorText, contains: "NSApplication.didResignActiveNotification")
        Self.assertSource(coordinatorText, contains: "NSApplication.willTerminateNotification")
        Self.assertSource(
            coordinatorText,
            contains: ".quillCodeDesktopWillTerminateForRelaunch"
        )
        Self.assertSource(modelText, contains: "ownerThreadID == root.selectedThreadID")
        Self.assertSource(modelText, contains: "threadPersistence.saveComposerDraft")
        Self.assertSource(persistenceText, contains: "maximumDraftBytes = 1 * 1_024 * 1_024")
        Self.assertSource(persistenceText, contains: "BoundedFileDataReader.readIfPresent")
        Self.assertSource(persistenceText, contains: "filePermissions = 0o600")
        Self.assertSource(downloadsText, contains: "Confidential and side-conversation drafts remain memory-only")
        Self.assertSource(crashSmokeText, contains: "Darwin.kill(getpid(), SIGKILL)")
        Self.assertSource(crashSmokeText, contains: "controller.model.composer.draft == expectedDraft")
        Self.assertSource(crashSmokeText, contains: "controller.model.setDraft(\"\")")
        Self.assertSource(
            appText,
            contains: "QuillCodeDesktopComposerDraftCrashSmoke.runAndExit"
        )
        Self.assertSource(packagedSmokeText, contains: "--composer-draft-crash-phase write")
        Self.assertSource(packagedSmokeText, contains: "--composer-draft-crash-phase verify")
        Self.assertSource(packagedSmokeText, contains: "COMPOSER_DRAFT_CRASH_STATUS\" -ne 137")
    }

    func testPackagedDesktopRecoversInterruptedAgentRunAfterHardKill() throws {
        let crashSmokeText = try Self.desktopSourceText(
            named: "QuillCodeDesktopAgentRunCrashSmoke.swift"
        )
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let packagedSmokeText = try Self.scriptText(named: "packaged-macos-smoke.sh")

        Self.assertSource(crashSmokeText, contains: "Darwin.kill(getpid(), SIGKILL)")
        Self.assertSource(crashSmokeText, contains: "activeRunCheckpoint == nil")
        Self.assertSource(crashSmokeText, contains: "toolCards.last?.status == .failed")
        Self.assertSource(crashSmokeText, contains: "failedRunRetryPrompt")
        Self.assertSource(crashSmokeText, contains: "crash-child.pid")
        Self.assertSource(crashSmokeText, contains: "guard !processIsAlive(childPID)")
        Self.assertSource(appText, contains: "QuillCodeDesktopAgentRunCrashSmoke.runAndExit")
        Self.assertSource(packagedSmokeText, contains: "--agent-run-crash-phase write")
        Self.assertSource(packagedSmokeText, contains: "--agent-run-crash-phase verify")
        Self.assertSource(packagedSmokeText, contains: "AGENT_RUN_CRASH_STATUS\" -ne 137")
    }
}
