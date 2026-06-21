import XCTest

final class ParityGateTests: XCTestCase {
    func testQuillCodeAppHasNoLinuxConditionals() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in ["DECISIONS.md", "CODEX_RESEARCH.md", "CODEX_PARITY_MATRIX.md", "ROADMAP.md", "TEST_PLAN.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/\(name)").path), name)
        }
    }

    func testDesktopDefinesNativeMenuBarWidget() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let desktopSource = root.appendingPathComponent("Sources/quill-code-desktop/main.swift")
        let text = try String(contentsOf: desktopSource, encoding: .utf8)

        XCTAssertTrue(text.contains("MenuBarExtra"), "Desktop app should define a native menu-bar widget.")
        XCTAssertTrue(text.contains(#"systemImage: "q.circle.fill""#), "Menu-bar widget should use a visible QuillCode symbol.")
        for label in ["New Chat", "Open Project", "Command Palette", "Computer Use Setup", "Settings", "Stop All", "Disconnect All"] {
            XCTAssertTrue(text.contains(label), "Menu-bar widget is missing \(label).")
        }
    }

    func testDesktopTrustedRouterSignInUsesLoopbackOAuth() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let desktopSource = root.appendingPathComponent("Sources/quill-code-desktop/main.swift")
        let text = try String(contentsOf: desktopSource, encoding: .utf8)

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
}
