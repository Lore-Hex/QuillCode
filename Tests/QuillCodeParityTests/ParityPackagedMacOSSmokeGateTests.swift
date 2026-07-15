import XCTest

final class ParityPackagedMacOSSmokeGateTests: QuillCodeParityTestCase {
    func testPackagedMacOSSmokeIncludesLiveWindowProof() throws {
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let supportText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeSupport.swift")
        let windowSmokeText = try Self.desktopSourceText(named: "QuillCodeDesktopWindowSmokeRunner.swift")
        let packagedSmoke = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("scripts/packaged-macos-smoke.sh"),
            encoding: .utf8
        )
        let clickProbeValidator = try Self.nativeClickProbeValidatorText()

        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeRequest(arguments: CommandLine.arguments)"))
        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeWorkspaceRoot(request: windowRequest)"))
        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeLaunch.schedule("))
        XCTAssertTrue(appText.contains("NSApplication.didFinishLaunchingNotification"))
        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeRunner.runAndExit("))
        XCTAssertTrue(appText.contains(".defaultSize(width: 1280, height: 900)"))
        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopWindowSmokeRequest"))
        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopWindowSmokeReport"))
        XCTAssertTrue(supportText.contains("enum QuillCodeDesktopNativeHitTargetSmoke"))
        XCTAssertTrue(supportText.contains(#""nativeHitTargets": nativeHitTargets.dictionary"#))
        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopWindowSmokeSurfaceReport"))
        XCTAssertTrue(supportText.contains("requiredCommandIDs"))
        XCTAssertTrue(supportText.contains("requiredStarterActionIDs"))
        XCTAssertTrue(supportText.contains(#""surface": surface.dictionary"#))
        XCTAssertTrue(windowSmokeText.contains("waitForWindow(controller: controller)"))
        XCTAssertTrue(windowSmokeText.contains("openSmokeWindow(controller: controller)"))
        XCTAssertTrue(windowSmokeText.contains("smokeController"))
        XCTAssertFalse(windowSmokeText.contains("QuillCodeDesktopController()"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopWindowSmokeSurfaceReport(surface: workspaceSurface)"))
        XCTAssertTrue(windowSmokeText.contains("NSHostingView(rootView: rootView)"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopRootView(controller: controller)"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopNativeHitTargetSmoke.validatedReport"))
        XCTAssertTrue(windowSmokeText.contains("bitmapImageRepForCachingDisplay"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopSmokePixelStats"))
        XCTAssertTrue(windowSmokeText.contains("window.title == \"QuillCode\""))
        XCTAssertTrue(packagedSmoke.contains("wait_for_smoke_process"))
        XCTAssertTrue(packagedSmoke.contains("--native-window-smoke"))
        XCTAssertTrue(packagedSmoke.contains("--window-smoke-report \"$WINDOW_REPORT_PATH\""))
        XCTAssertTrue(packagedSmoke.contains("--window-smoke-screenshot \"$WINDOW_SCREENSHOT_PATH\""))
        XCTAssertTrue(packagedSmoke.contains("--window-smoke-state-root \"$WINDOW_STATE_ROOT\""))
        XCTAssertFalse(packagedSmoke.contains("HOME=\"$SMOKE_ROOT/home\""))
        XCTAssertTrue(packagedSmoke.contains("window-report.json"))
        XCTAssertTrue(packagedSmoke.contains("window.png"))
        XCTAssertTrue(packagedSmoke.contains("packaged-accessibility-frames.json"))
        XCTAssertTrue(packagedSmoke.contains("accessibility_frames_manifest=packaged-accessibility-frames.json"))
        XCTAssertTrue(packagedSmoke.contains(" frames \\"))
        XCTAssertTrue(packagedSmoke.contains("$WINDOW_REPORT_PATH"))
        XCTAssertTrue(packagedSmoke.contains("$WINDOW_SCREENSHOT_PATH"))
        XCTAssertTrue(packagedSmoke.contains("--click-probe-manifest \"$CLICK_PROBE_MANIFEST\""))
        XCTAssertTrue(packagedSmoke.contains("--manifest \"$ACCESSIBILITY_FRAMES_MANIFEST\""))
        Self.assertSource(packagedSmoke, excludes: "python3 - \"$WINDOW_REPORT_PATH\"")
        XCTAssertTrue(clickProbeValidator.contains(#"def validate_packaged_window_report"#))
        XCTAssertTrue(clickProbeValidator.contains(#"def write_accessibility_frames_manifest"#))
        XCTAssertTrue(clickProbeValidator.contains(#"live-accessibility-frame-sampled"#))
        XCTAssertTrue(clickProbeValidator.contains(#"REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS"#))
        XCTAssertTrue(clickProbeValidator.contains(#"windowTitle") == "QuillCode""#))
        XCTAssertTrue(clickProbeValidator.contains(#"normalized_probe_contracts(report, "packaged live-window")"#))
        XCTAssertTrue(clickProbeValidator.contains(#"composerCanSend") is False"#))
        XCTAssertTrue(clickProbeValidator.contains(#"sidebarTitle") == "Chats""#))
        for commandID in ["new-chat", "command-palette", "keyboard-shortcuts", "settings", "toggle-terminal", "toggle-browser", "stop-all", "disconnect-all"] {
            Self.assertSource(clickProbeValidator, contains: commandID)
        }
        for actionID in ["review-changes", "run-tests", "explain-project"] {
            Self.assertSource(clickProbeValidator, contains: actionID)
        }
    }

}
