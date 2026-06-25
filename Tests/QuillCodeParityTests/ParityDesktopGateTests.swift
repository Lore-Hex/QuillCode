import XCTest

final class ParityDesktopGateTests: QuillCodeParityTestCase {
    func testDesktopDefinesNativeMenuBarWidget() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("MenuBarExtra"), "Desktop app should define a native menu-bar widget.")
        XCTAssertTrue(text.contains(#"systemImage: "q.circle.fill""#), "Menu-bar widget should use a visible QuillCode symbol.")
        for label in ["New Chat", "Open Project", "Command Palette", "Keyboard Shortcuts", "Open Browser Session", "Computer Use Setup", "Settings", "Stop All", "Disconnect All"] {
            XCTAssertTrue(text.contains(label), "Menu-bar widget is missing \(label).")
        }

        let menuText = try Self.desktopSourceText(named: "QuillCodeMenuBarView.swift")
        XCTAssertTrue(menuText.contains("onDisconnectAll"), "Disconnect All should be wired to a controller action.")
        XCTAssertTrue(menuText.contains("onOpenBrowserSession"), "Visible browser session should be wired to a controller action.")
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
        let browserCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let composerCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopComposerCoordinator.swift")
        let terminalCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopTerminalCoordinator.swift")
        let desktopTaskText = try Self.desktopSourceText(named: "QuillCodeDesktopTaskCoordinator.swift")
        let sharedTaskText = try Self.appSourceText(named: "QuillCodeTaskCoordinator.swift")
        let sharedTaskTests = try Self.appTestSourceText(named: "QuillCodeTaskCoordinatorTests.swift")

        XCTAssertTrue(text.contains("QuillCodeDesktopTaskCoordinator"), "Desktop cancellable tasks should be isolated behind a coordinator.")
        XCTAssertTrue(sharedTaskText.contains("public final class QuillCodeTaskCoordinator"), "Reusable cancellable task coordination should live in the app layer.")
        XCTAssertTrue(desktopTaskText.contains("QuillCodeTaskCoordinator<Slot>"), "Desktop task slots should delegate to the shared task coordinator.")
        XCTAssertTrue(sharedTaskText.contains("guard self?.finish(slot, id: id) == true else { return }"), "Cancelled or replaced tasks must not run stale finish callbacks.")
        XCTAssertTrue(sharedTaskTests.contains("testReplaceCancelsStaleTaskAndOnlyFinishesCurrentTask"), "Task replacement semantics need focused regression coverage.")
        XCTAssertTrue(controllerText.contains("QuillCodeDesktopComposerCoordinator"), "Desktop composer send/retry workflow should be isolated behind a coordinator.")
        XCTAssertTrue(controllerText.contains("composerCoordinator.send"), "Desktop controller should delegate composer sends.")
        XCTAssertTrue(controllerText.contains("composerCoordinator.retryLastTurn"), "Desktop controller should delegate composer retries.")
        XCTAssertTrue(composerCoordinatorText.contains("tasks.startIfIdle(.send"), "Composer sends should use the task coordinator.")
        XCTAssertTrue(composerCoordinatorText.contains("draft.trimmingCharacters(in: .whitespacesAndNewlines)"), "Composer coordinator should normalize submitted prompts.")
        XCTAssertTrue(composerCoordinatorText.contains("model.prepareRetryLastUserTurn()"), "Composer retry preparation should live in the composer coordinator.")
        XCTAssertTrue(controllerText.contains("QuillCodeDesktopTerminalCoordinator"), "Desktop terminal workflow should be isolated behind a coordinator.")
        XCTAssertTrue(controllerText.contains("terminalCoordinator.runCommand"), "Desktop controller should delegate terminal command execution.")
        XCTAssertTrue(controllerText.contains("terminalCoordinator.recallPreviousCommand"), "Desktop controller should delegate terminal history recall.")
        XCTAssertTrue(terminalCoordinatorText.contains("tasks.startIfIdle(.terminal"), "Terminal runs should use the task coordinator.")
        XCTAssertTrue(terminalCoordinatorText.contains("draft.trimmingCharacters(in: .whitespacesAndNewlines)"), "Terminal coordinator should normalize submitted commands.")
        XCTAssertTrue(terminalCoordinatorText.contains("model.setTerminalDraft(draft)"), "Terminal history recall should sync unsent UI draft before moving through history.")
        XCTAssertTrue(browserCoordinatorText.contains("tasks.replace(.browserPreview"), "Browser previews should replace stale preview work.")
        XCTAssertTrue(controllerText.contains("tasks.replace(.automationTicker"), "Automation ticks should use the task coordinator.")
        XCTAssertFalse(desktopTaskText.contains("private var tasks"), "Desktop wrapper should not own raw task storage.")
        XCTAssertFalse(controllerText.contains("private var sendTask"), "Desktop controller should not own raw send task slots.")
        XCTAssertFalse(controllerText.contains("private var terminalTask"), "Desktop controller should not own raw terminal task slots.")
        XCTAssertFalse(controllerText.contains("private var browserPreviewTask"), "Desktop controller should not own raw browser-preview task slots.")
        XCTAssertFalse(controllerText.contains("sendTaskID"), "Desktop controller should not own manual task identity bookkeeping.")
        XCTAssertFalse(controllerText.contains("let prompt = draft.trimmingCharacters"), "Desktop controller should not own composer prompt normalization.")
        XCTAssertFalse(controllerText.contains("model.prepareRetryLastUserTurn()"), "Desktop controller should not own retry preparation.")
        XCTAssertFalse(controllerText.contains("let command = terminalDraft.trimmingCharacters"), "Desktop controller should not own terminal command normalization.")
    }

    func testDesktopBrowserLiveDOMCaptureUsesFocusedAdapter() throws {
        let desktopText = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let browserCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let capturerText = try Self.desktopSourceText(named: "DesktopBrowserLiveDOMCapturer.swift")

        XCTAssertTrue(desktopText.contains("QuillCodeDesktopBrowserCoordinator"), "Desktop browser preview workflow should be isolated behind a coordinator.")
        XCTAssertTrue(desktopText.contains("DesktopBrowserLiveDOMCapturer"), "Desktop should provide a native rendered-browser capture adapter.")
        XCTAssertTrue(capturerText.contains("BrowserLiveDOMCapturing"), "Desktop live DOM capture should implement the shared adapter protocol.")
        XCTAssertTrue(capturerText.contains("WKWebView"), "Desktop live DOM capture should render pages before inspecting DOM.")
        XCTAssertTrue(capturerText.contains("evaluateJavaScript"), "Desktop live DOM capture should inspect the rendered page DOM.")
        XCTAssertTrue(capturerText.contains("enum DesktopBrowserLiveDOMProfile"), "Desktop live DOM capture should make browser profile persistence explicit.")
        XCTAssertTrue(capturerText.contains("case persistent"), "Desktop live DOM capture should support persistent signed-in browser profile state.")
        XCTAssertTrue(capturerText.contains("case ephemeral"), "Desktop live DOM capture should keep an explicit non-persistent option for future privacy/test controls.")
        XCTAssertTrue(capturerText.contains("profile: DesktopBrowserLiveDOMProfile = .persistent"), "Desktop live DOM capture should default to a persistent profile.")
        XCTAssertTrue(capturerText.contains("WKWebsiteDataStore"), "Desktop live DOM profile selection should be backed by WebKit data stores.")
        XCTAssertTrue(capturerText.contains("return .default()"), "Persistent desktop browser capture should reuse WebKit's default cookie/session store.")
        XCTAssertTrue(controllerText.contains("browserLiveDOMCapturer"), "Desktop controller should accept live DOM capture as an injectable dependency.")
        XCTAssertTrue(controllerText.contains("browserCoordinator.openPreview"), "Desktop controller should delegate browser preview workflow.")
        XCTAssertTrue(
            browserCoordinatorText.contains("refreshRenderedBrowserSnapshot(capturer: liveDOMCapturer)"),
            "Desktop browser preview coordinator should upgrade fetched snapshots with rendered live DOM when available."
        )
        XCTAssertFalse(controllerText.contains("WKWebView"), "Desktop controller should not own WebKit rendering details.")
        XCTAssertFalse(controllerText.contains("evaluateJavaScript"), "Desktop controller should not own DOM capture details.")
        XCTAssertFalse(controllerText.contains("import WebKit"), "Desktop controller should not import WebKit.")
        XCTAssertFalse(controllerText.contains("document.body"), "Desktop controller should not embed browser JavaScript.")
    }

    func testDesktopBrowserVisibleSessionUsesFocusedAdapter() throws {
        let desktopText = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let browserCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let presenterText = try Self.desktopSourceText(named: "DesktopBrowserSessionPresenter.swift")
        let browserPaneText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")
        let commandCatalogText = try Self.appSourceText(named: "WorkspaceCommandStaticCatalog.swift")
        let viewCommandPlannerText = try Self.appSourceText(named: "QuillCodeWorkspaceViewCommandPlanner.swift")

        XCTAssertTrue(desktopText.contains("DesktopBrowserSessionPresenter"), "Desktop should provide a visible browser session adapter.")
        XCTAssertTrue(presenterText.contains("protocol DesktopBrowserSessionPresenting"), "Visible browser sessions should be isolated behind an injectable protocol.")
        XCTAssertTrue(presenterText.contains("WKWebView"), "Visible browser sessions should render with WebKit on desktop.")
        XCTAssertTrue(presenterText.contains("configuration.websiteDataStore = .default()"), "Visible browser sessions should share the persistent WebKit profile.")
        XCTAssertTrue(presenterText.contains("loadFileURL"), "Visible browser sessions should support local file previews.")
        XCTAssertTrue(presenterText.contains("private var session: DesktopBrowserSessionWindowController?"), "Visible browser sessions should reuse a retained session window.")
        XCTAssertTrue(presenterText.contains("session.navigate(to: url)"), "Repeated visible browser session opens should navigate the existing window.")
        XCTAssertTrue(presenterText.contains("func present()"), "Visible browser session focus behavior should stay inside the presenter adapter.")
        XCTAssertFalse(presenterText.contains("sessions: [ObjectIdentifier"), "Visible browser sessions should not regress to one retained window per click.")
        XCTAssertTrue(controllerText.contains("browserSessionPresenter"), "Desktop controller should accept a visible browser session dependency.")
        XCTAssertTrue(controllerText.contains("browserCoordinator.openSession"), "Desktop controller should delegate visible browser session workflow.")
        XCTAssertTrue(browserCoordinatorText.contains("WorkspaceBrowserLocationResolver(workspaceRoot: root).resolve"), "Visible browser session URLs should share preview address resolution.")
        XCTAssertTrue(controllerText.contains("func openBrowserSession()"), "Desktop controller should expose a visible browser session action.")
        XCTAssertTrue(appText.contains("onOpenBrowserSession: controller.openBrowserSession"), "Desktop app should wire visible browser sessions into shared UI.")
        XCTAssertTrue(browserPaneText.contains("var onOpenSession: (() -> Void)?"), "Shared browser pane should keep visible sessions optional for non-desktop platforms.")
        XCTAssertTrue(browserPaneText.contains(#"Button("Session", action: onOpenSession)"#), "Browser pane should expose a compact visible session action when available.")
        XCTAssertTrue(commandCatalogText.contains(#"id: "open-browser-session""#), "Command palette should expose visible browser sessions.")
        XCTAssertTrue(commandCatalogText.contains("browserCanOpenSession"), "Visible browser session command should use real browser availability.")
        XCTAssertTrue(viewCommandPlannerText.contains(#"case "open-browser-session":"#), "Shared command routing should present visible sessions without falling through to text insertion.")
        XCTAssertFalse(controllerText.contains("WKWebView"), "Desktop controller should not own WebKit visible-session details.")
        XCTAssertFalse(controllerText.contains("import WebKit"), "Desktop controller should not import WebKit.")
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
        XCTAssertTrue(plannerText.contains("case \"open-browser-session\""), "Visible browser sessions should be a typed desktop command.")
        XCTAssertTrue(controllerText.contains("case .openBrowserSession:"), "Desktop controller should execute visible browser session actions.")
        XCTAssertTrue(plannerText.contains("WorkspaceCommandRoutingCatalog.canRunInWorkspaceModel"), "Desktop command fallback should only delegate command IDs the workspace model can execute.")
        XCTAssertTrue(controllerText.contains("guard let action = QuillCodeDesktopCommandPlanner.action(for: command) else { return }"), "Unknown desktop commands should return without becoming silent workspace no-ops.")
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
