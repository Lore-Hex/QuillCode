import XCTest

final class ParityDesktopGateTests: QuillCodeParityTestCase {
    func testDesktopDefinesNativeMenuBarWidget() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("MenuBarExtra"), "Desktop app should define a native menu-bar widget.")
        XCTAssertTrue(text.contains(#"systemImage: "q.circle.fill""#), "Menu-bar widget should use a visible QuillCode symbol.")
        for label in ["New Chat", "Open Project", "Command Palette", "Keyboard Shortcuts", "Computer Use Setup", "Settings", "Stop All", "Disconnect All"] {
            XCTAssertTrue(text.contains(label), "Menu-bar widget is missing \(label).")
        }

        let menuText = try Self.desktopSourceText(named: "QuillCodeMenuBarView.swift")
        XCTAssertTrue(menuText.contains("onDisconnectAll"), "Disconnect All should be wired to a controller action.")
        XCTAssertFalse(menuText.contains(#"Button("Disconnect All") {}"#), "Disconnect All must not regress to a no-op button.")
        XCTAssertFalse(menuText.contains(".disabled(true)"), "Menu-bar actions should be disabled from real command state, not permanently.")
    }

    func testDesktopTrustedRouterSignInUsesLoopbackOAuth() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopSignInCoordinator"), "Desktop sign-in should be isolated from UI routing.")
        XCTAssertTrue(text.contains("TrustedRouterLoopbackCallbackServer"), "Desktop sign-in should own a loopback callback server.")
        XCTAssertTrue(text.contains("TrustedRouterDefaults.loopbackCallbackURL"), "Desktop sign-in should use the shared TrustedRouter loopback callback URL.")
        XCTAssertTrue(text.contains("createAuthorization"), "Desktop sign-in should construct a PKCE authorization URL.")
        XCTAssertTrue(text.contains("exchangeCode"), "Desktop sign-in should exchange the callback code for a scoped key.")
        XCTAssertTrue(text.contains("saveTrustedRouterAPIKey"), "Desktop sign-in should persist the returned TrustedRouter key.")
        XCTAssertTrue(text.contains("fetchModelCatalog"), "Desktop sign-in should refresh the model catalog after storing the key.")
        XCTAssertFalse(controllerText.contains("exchangeCode"), "Desktop controller should delegate OAuth exchange work.")
        XCTAssertFalse(controllerText.contains("TrustedRouterOAuthClient"), "Desktop controller should not own OAuth client construction.")
        XCTAssertFalse(controllerText.contains("TrustedRouterLoopbackCallbackServer"), "Desktop controller should not own loopback callback capture.")
        XCTAssertFalse(
            text.contains("NSWorkspace.shared.open(url)") && text.contains("TrustedRouterDefaults.signInURL"),
            "Desktop sign-in should not regress to opening the static sign-in documentation page."
        )
    }

    func testDesktopControllerDelegatesCancellableTaskSlots() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopTaskCoordinator"), "Desktop cancellable tasks should be isolated behind a coordinator.")
        XCTAssertTrue(controllerText.contains("tasks.startIfIdle(.send"), "Composer sends should use the task coordinator.")
        XCTAssertTrue(controllerText.contains("tasks.startIfIdle(.terminal"), "Terminal runs should use the task coordinator.")
        XCTAssertTrue(controllerText.contains("tasks.replace(.browserPreview"), "Browser previews should replace stale preview work.")
        XCTAssertTrue(controllerText.contains("tasks.replace(.automationTicker"), "Automation ticks should use the task coordinator.")
        XCTAssertFalse(controllerText.contains("private var sendTask"), "Desktop controller should not own raw send task slots.")
        XCTAssertFalse(controllerText.contains("private var terminalTask"), "Desktop controller should not own raw terminal task slots.")
        XCTAssertFalse(controllerText.contains("private var browserPreviewTask"), "Desktop controller should not own raw browser-preview task slots.")
        XCTAssertFalse(controllerText.contains("sendTaskID"), "Desktop controller should not own manual task identity bookkeeping.")
    }

    func testDesktopControllerDelegatesSettingsPersistenceAndSystemSettings() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopSettingsCoordinator"), "Desktop settings persistence should be isolated from UI routing.")
        XCTAssertTrue(text.contains("MacSystemSettingsOpener"), "macOS System Settings URLs should be isolated behind a platform opener.")
        XCTAssertTrue(controllerText.contains("settingsCoordinator.apply"), "Settings saves should use the settings coordinator.")
        XCTAssertTrue(controllerText.contains("systemSettingsOpener.open"), "Computer Use system settings routing should use the platform opener.")
        XCTAssertFalse(controllerText.contains("saveTrustedRouterAPIKey"), "Desktop controller should not persist secret keys directly.")
        XCTAssertFalse(controllerText.contains("clearTrustedRouterAPIKey"), "Desktop controller should not clear secret keys directly.")
        XCTAssertFalse(controllerText.contains("trustedRouterAccount = nil"), "Desktop controller should not own auth-account reset rules.")
        XCTAssertFalse(controllerText.contains("NSWorkspace.shared.open"), "Desktop controller should not open platform settings directly.")
        XCTAssertFalse(controllerText.contains("x-apple.systempreferences"), "Desktop controller should not own macOS System Settings URLs.")
        XCTAssertFalse(controllerText.contains("Privacy_ScreenCapture"), "Desktop controller should not own Screen Recording pane URLs.")
        XCTAssertFalse(controllerText.contains("Privacy_Accessibility"), "Desktop controller should not own Accessibility pane URLs.")
    }

    func testDesktopControllerDelegatesTranscriptCopyFeedback() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let copyText = try Self.desktopSourceText(named: "QuillCodeDesktopCopyCoordinator.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopCopyCoordinator"), "Desktop transcript copy behavior should be isolated from UI routing.")
        XCTAssertTrue(copyText.contains("protocol QuillCodePasteboardWriting"), "Pasteboard writes should be isolated behind an injectable protocol.")
        XCTAssertTrue(copyText.contains("struct MacPasteboardWriter"), "Concrete macOS pasteboard access should live in a focused adapter.")
        XCTAssertTrue(copyText.contains("struct QuillCodeDesktopCopyFeedback"), "Transient copy feedback should be represented as a value.")
        XCTAssertTrue(copyText.contains("defaultFeedbackDurationNanoseconds"), "Copy feedback timing should live beside copy behavior.")
        XCTAssertTrue(controllerText.contains("copyCoordinator.copyTranscriptItem"), "Desktop controller should delegate transcript copying.")
        XCTAssertTrue(controllerText.contains("feedback.clearAfterNanoseconds"), "Desktop controller should consume the coordinator's feedback timing.")
        XCTAssertFalse(controllerText.contains("NSPasteboard"), "Desktop controller should not write the pasteboard directly.")
        XCTAssertFalse(controllerText.contains("clearContents()"), "Desktop controller should not own pasteboard mutation details.")
        XCTAssertFalse(controllerText.contains("setString(text, forType: .string)"), "Desktop controller should not own pasteboard mutation details.")
        XCTAssertFalse(controllerText.contains("1_500_000_000"), "Desktop controller should not own copy-feedback timing literals.")
        XCTAssertFalse(controllerText.contains("import AppKit"), "Desktop controller should not import AppKit for copy behavior.")
    }

    func testDesktopControllerDelegatesProjectImportResolution() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let importText = try Self.desktopSourceText(named: "QuillCodeDesktopProjectImportCoordinator.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopProjectImportCoordinator"), "Desktop project import resolution should be isolated from UI routing.")
        XCTAssertTrue(importText.contains("struct QuillCodeDesktopProjectImportSelection"), "Project import selection should be represented as a value.")
        XCTAssertTrue(importText.contains("func selectedProject(from result:"), "Project import resolution should live in the coordinator.")
        XCTAssertTrue(importText.contains("fileExists(atPath: url.path, isDirectory:"), "Project import resolution should validate real directories.")
        XCTAssertTrue(controllerText.contains("projectImportCoordinator.selectedProject"), "Desktop controller should delegate project import result handling.")
        XCTAssertFalse(controllerText.contains("guard case let .success(urls)"), "Desktop controller should not parse file-import results directly.")
        XCTAssertFalse(controllerText.contains("urls.first"), "Desktop controller should not choose imported URLs directly.")
        XCTAssertFalse(controllerText.contains("fileExists(atPath:"), "Desktop controller should not own import directory validation.")
    }

    func testDesktopControllerDelegatesCommandPlanning() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let plannerText = try Self.desktopSourceText(named: "QuillCodeDesktopCommandPlanner.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopCommandPlanner"), "Desktop command routing should be isolated from the controller.")
        XCTAssertTrue(plannerText.contains("enum QuillCodeDesktopCommandAction"), "Desktop command actions should be typed values.")
        XCTAssertTrue(plannerText.contains("static func action(for command: WorkspaceCommandSurface)"), "Desktop command planning should be directly inspectable.")
        XCTAssertTrue(plannerText.contains("case \"computer-use-open-screen-recording\""), "Computer Use settings command IDs should live in the desktop planner.")
        XCTAssertTrue(plannerText.contains("return .workspaceCommand(command.id)"), "Unknown desktop commands should still delegate to workspace command execution.")
        XCTAssertTrue(controllerText.contains("QuillCodeDesktopCommandPlanner.action(for: command)"), "Desktop controller should consume the command planner.")
        XCTAssertFalse(controllerText.contains("switch command.id"), "Desktop controller should not switch over raw command IDs.")
        XCTAssertFalse(controllerText.contains("case \"computer-use-open-screen-recording\""), "Desktop controller should not own Computer Use command IDs.")
        XCTAssertFalse(controllerText.contains("case \"retry-last-turn\""), "Desktop controller should not own retry command IDs.")
    }

    func testDesktopNotifiesWhenDueAutomationsRun() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("UNUserNotificationCenter"), "Desktop app should use native notifications for due automations.")
        XCTAssertTrue(text.contains("MacAutomationNotifier"), "Desktop app should isolate notification delivery behind an adapter.")
        XCTAssertTrue(text.contains("runDueAutomationReports"), "Desktop app should consume structured automation run reports.")
        XCTAssertTrue(text.contains("automationNotifier.deliver"), "Desktop app should deliver a notification for each due automation report.")
    }
}
