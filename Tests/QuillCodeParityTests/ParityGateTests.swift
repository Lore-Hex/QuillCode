import XCTest

final class ParityGateTests: XCTestCase {
    func testQuillCodeAppHasNoLinuxConditionals() throws {
        let packageRoot = Self.packageRoot()
        let sourceRoots = [
            packageRoot.appendingPathComponent("Sources/QuillCodeApp"),
            packageRoot.appendingPathComponent("Sources/quill-code-desktop")
        ]
        let files = try sourceRoots.flatMap { root in
            try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "swift" }
        }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("#if os(Linux)"), "\(file.path) contains app-level Linux conditional")
            XCTAssertFalse(text.contains("#if linux"), "\(file.path) contains app-level Linux conditional")
        }
    }

    func testParityDocsExist() {
        let root = Self.packageRoot()
        for name in ["DECISIONS.md", "CODEX_RESEARCH.md", "CODEX_PARITY_MATRIX.md", "ROADMAP.md", "TEST_PLAN.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/\(name)").path), name)
        }
    }

    func testWorkspaceModelDelegatesToolCardSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")

        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolCardState"), "Tool card surface state should live in a focused surface file.")
        XCTAssertTrue(toolCardSurfaceText.contains("public struct ToolArtifactState"), "Tool artifact surface state should live in a focused surface file.")
        XCTAssertTrue(toolCardSurfaceText.contains("enum ToolArtifactPreviewBuilder"), "Tool artifact preview construction should live beside artifact state.")
        XCTAssertTrue(modelText.contains("ToolArtifactPreviewBuilder.textPreview"), "WorkspaceModel should request artifact previews through the extracted builder.")
        XCTAssertFalse(modelText.contains("public struct ToolCardState"), "WorkspaceModel should not own tool card surface state.")
        XCTAssertFalse(modelText.contains("public enum ToolCardStatus"), "WorkspaceModel should not own tool card status.")
        XCTAssertFalse(modelText.contains("public struct ToolArtifactState"), "WorkspaceModel should not own tool artifact surface state.")
    }

    func testDesktopDefinesNativeMenuBarWidget() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("MenuBarExtra"), "Desktop app should define a native menu-bar widget.")
        XCTAssertTrue(text.contains(#"systemImage: "q.circle.fill""#), "Menu-bar widget should use a visible QuillCode symbol.")
        for label in ["New Chat", "Open Project", "Command Palette", "Keyboard Shortcuts", "Computer Use Setup", "Settings", "Stop All", "Disconnect All"] {
            XCTAssertTrue(text.contains(label), "Menu-bar widget is missing \(label).")
        }
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

    func testDesktopNotifiesWhenDueAutomationsRun() throws {
        let text = try Self.desktopSourceText()

        XCTAssertTrue(text.contains("UNUserNotificationCenter"), "Desktop app should use native notifications for due automations.")
        XCTAssertTrue(text.contains("MacAutomationNotifier"), "Desktop app should isolate notification delivery behind an adapter.")
        XCTAssertTrue(text.contains("runDueAutomationReports"), "Desktop app should consume structured automation run reports.")
        XCTAssertTrue(text.contains("automationNotifier.deliver"), "Desktop app should deliver a notification for each due automation report.")
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func desktopSourceText() throws -> String {
        let root = packageRoot().appendingPathComponent("Sources/quill-code-desktop")
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }

    private static func desktopSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/quill-code-desktop")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func appSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeApp")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }
}
