import XCTest

final class ParityPublicDistributionGateTests: QuillCodeParityTestCase {
    func testReadmeLeadsWithAUsablePublicMacDistribution() throws {
        let root = Self.packageRoot()
        let readme = try String(
            contentsOf: root.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        XCTAssertTrue(readme.hasPrefix("# Quill Cowork\n"))
        Self.assertSource(
            readme,
            containsAll: [
                "releases/download/tester-latest/Quill-Cowork-macOS-universal.dmg",
                "releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg",
                "releases/download/tester-latest/Quill-Cowork-macOS-x86_64.dmg",
                "releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip",
                "releases/download/tester-latest/Quill-Cowork-macOS-x86_64.zip",
                "docs/images/quill-cowork-desktop.png",
                "macOS 14 or later",
                "Apple silicon and Intel Macs",
                "drag **Quill Cowork.app** onto **Applications**",
                "checks for updates automatically",
                "activation is atomic",
                "not Apple-notarized yet"
            ]
        )
        Self.assertSource(readme, excludes: "The long-term target")
        Self.assertSource(readme, excludes: "This initial repository contains")
        Self.assertSource(readme, excludes: "http://localhost:3000/callback")
    }

    func testReadmeScreenshotIsARealPNGAsset() throws {
        let screenshotURL = Self.packageRoot()
            .appendingPathComponent("docs/images/quill-cowork-desktop.png")
        let screenshot = try Data(contentsOf: screenshotURL)

        XCTAssertGreaterThan(screenshot.count, 40_000)
        XCTAssertTrue(screenshot.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testFirstRunConnectSurfaceHidesDeveloperCallbackDetails() throws {
        let connectView = try Self.appSourceText(named: "QuillCodeConnectView.swift")
        let connectBannerView = try Self.appSourceText(named: "QuillCodeConnectBannerView.swift")
        let connectPrompt = try Self.appSourceText(named: "TranscriptConnectPrompt.swift")
        let settingsView = try Self.appSourceText(named: "QuillCodeSettingsView.swift")
        let workspaceView = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let workspaceSheets = try Self.appSourceText(named: "QuillCodeWorkspaceSheets.swift")

        Self.assertSource(connectView, excludes: "prompt.signInURL")
        Self.assertSource(connectView, containsAll: [
            "TranscriptConnectPrompt.developerKeyTitle",
            "quillcode-connect-developer-key",
            "onUseDeveloperKey"
        ])
        Self.assertSource(connectBannerView, containsAll: [
            "TranscriptConnectPrompt.returningUserSubtitle",
            "quillcode-connect-sign-in",
            "quillcode-connect-developer-key"
        ])
        Self.assertSource(connectPrompt, contains: "case banner")
        Self.assertSource(connectPrompt, excludes: "var signInURL")
        Self.assertSource(settingsView, contains: "Text(settings.signInURL)")
        Self.assertSource(settingsView, containsAll: [
            "LazyVStack(alignment: .leading, spacing: 14)",
            "authenticationSection",
            "QuillCodeNotificationSettingsCard"
        ])
        let authenticationIndex = try XCTUnwrap(settingsView.range(of: "authenticationSection")).lowerBound
        let notificationIndex = try XCTUnwrap(
            settingsView.range(of: "QuillCodeNotificationSettingsCard")
        ).lowerBound
        XCTAssertLessThan(authenticationIndex, notificationIndex)
        Self.assertSource(workspaceView, containsAll: [
            "onUseDeveloperKey: presentDeveloperKeySettings",
            "settingsAuthModeOverride = .developerOverride"
        ])
        Self.assertSource(workspaceSheets, contains: "authModeOverride: settingsAuthModeOverride")
    }

    func testNotificationServicesRequireCanonicalPackagedProcessIdentity() throws {
        let controller = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")

        Self.assertSource(controller, containsAll: [
            "QuillCodeDesktopPackagedProcessIdentity.ownsNotificationCenter(",
            #"pathExtension.caseInsensitiveCompare("app")"#,
            #"appendingPathComponent("Contents/MacOS", isDirectory: true)"#
        ])
        Self.assertSource(controller, excludesAll: [
            "guard bundle.bundleIdentifier == updateController.configuration?.bundleIdentifier else"
        ])
    }
}
