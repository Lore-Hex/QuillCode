import XCTest

final class ParityPackagedUpdaterGateTests: QuillCodeParityTestCase {
    func testPublishedBuildMustUpdateAndRelaunchItself() throws {
        let app = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let runner = try Self.desktopSourceText(named: "QuillCodeDesktopUpdaterSmokeRunner.swift")
        let script = try Self.scriptText(named: "packaged-macos-updater-smoke.sh")
        let workflow = try Self.workflowText(named: "download-builds.yml")

        Self.assertSource(app, containsAll: [
            "QuillCodeDesktopUpdaterSmokeRequest",
            "QuillCodeDesktopUpdaterSmokeRunner.runAndExit"
        ])
        Self.assertSource(runner, containsAll: [
            "QuillCodeDesktopUpdateChecker().check",
            "QuillCodeDesktopUpdatePreparer().prepare",
            "QuillCodeDesktopUpdateInstaller().stageAndLaunch",
            "targetCommit: release.commit"
        ])
        Self.assertSource(script, containsAll: [
            "--native-updater-smoke",
            "--updater-smoke-report",
            "codesign --verify --deep --strict",
            "CFBundleVersion $SOURCE_BUILD",
            "targetCommit",
            "STAGING_APPS",
            "Updated app did not remain running"
        ])
        Self.assertSource(workflow, containsAll: [
            "verify-updater:",
            "runs-on: macos-15",
            "needs: publish",
            "scripts/packaged-macos-updater-smoke.sh",
            "quillcode-public-updater-smoke"
        ])
    }
}
