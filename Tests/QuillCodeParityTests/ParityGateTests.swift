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

        XCTAssertTrue(text.contains("TrustedRouterLoopbackCallbackServer"), "Desktop sign-in should own a loopback callback server.")
        XCTAssertTrue(text.contains("TrustedRouterDefaults.loopbackCallbackURL"), "Desktop sign-in should use the shared TrustedRouter loopback callback URL.")
        XCTAssertTrue(text.contains("createAuthorization"), "Desktop sign-in should construct a PKCE authorization URL.")
        XCTAssertTrue(text.contains("exchangeCode"), "Desktop sign-in should exchange the callback code for a scoped key.")
        XCTAssertTrue(text.contains("saveTrustedRouterAPIKey"), "Desktop sign-in should persist the returned TrustedRouter key.")
        XCTAssertTrue(text.contains("fetchModelCatalog"), "Desktop sign-in should refresh the model catalog after storing the key.")
        XCTAssertFalse(
            text.contains("NSWorkspace.shared.open(url)") && text.contains("TrustedRouterDefaults.signInURL"),
            "Desktop sign-in should not regress to opening the static sign-in documentation page."
        )
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
}
