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
        let smokeText = try Self.desktopSourceText(named: "QuillCodeDesktopLaunchRecoverySmoke.swift")
        let reporterText = try Self.desktopSourceText(named: "QuillCodeDesktopIssueReporter.swift")

        Self.assertSource(appText, contains: "launchLifecycleController?.startIfNeeded()")
        Self.assertSource(rootViewText, contains: "launchLifecycleController?.markReady()")
        Self.assertSource(rootViewText, contains: "Quill Cowork closed unexpectedly")
        Self.assertSource(rootViewText, contains: "controller.launchLifecycleController?.takeUnexpectedExit()")
        Self.assertSource(rootViewText, contains: "QuillCodeDesktopIssueReporter.open(")
        Self.assertSource(lifecycleText, contains: "flock(descriptor, LOCK_EX)")
        Self.assertSource(lifecycleText, contains: "record.launchID == launchID")
        Self.assertSource(lifecycleText, contains: "processIsRunning(record.processIdentifier)")
        Self.assertSource(lifecycleText, contains: "NSApplication.willTerminateNotification")
        Self.assertSource(reporterText, contains: "## Previous session")
        Self.assertSource(appText, contains: "QuillCodeDesktopLaunchRecoverySmoke.runAndExit(request)")
        Self.assertSource(smokeText, contains: "try verify(home: root.home)")
    }
}
