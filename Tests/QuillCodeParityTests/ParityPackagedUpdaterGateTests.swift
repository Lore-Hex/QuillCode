import XCTest

final class ParityPackagedUpdaterGateTests: QuillCodeParityTestCase {
    func testPublishedBuildMustUpdateAndRelaunchItself() throws {
        let app = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let runner = try Self.desktopSourceText(named: "QuillCodeDesktopUpdaterSmokeRunner.swift")
        let script = try Self.scriptText(named: "packaged-macos-updater-smoke.sh")
        let workflow = try Self.workflowText(named: "download-builds.yml")

        Self.assertSource(app, containsAll: [
            "_ = QuillCodeDesktopLaunchClock.appEntryUptime",
            "QuillCodeDesktopUpdateLaunchHandshake.acknowledgeIfRequested()",
            "QuillCodeDesktopUpdaterSmokeRequest",
            "QuillCodeDesktopUpdaterSmokeRunner.runAndExit"
        ])
        let handshake = "QuillCodeDesktopUpdateLaunchHandshake.acknowledgeIfRequested()"
        XCTAssertEqual(app.components(separatedBy: handshake).count - 1, 1)
        let entryRange = try XCTUnwrap(app.range(of: "_ = QuillCodeDesktopLaunchClock.appEntryUptime"))
        let handshakeRange = try XCTUnwrap(app.range(of: handshake))
        let helperRange = try XCTUnwrap(app.range(of: "QuillCodeDesktopUpdateHelperRequest.parse"))
        XCTAssertLessThan(entryRange.lowerBound, handshakeRange.lowerBound)
        XCTAssertLessThan(handshakeRange.lowerBound, helperRange.lowerBound)
        Self.assertSource(runner, containsAll: [
            "waitForAvailableUpdate(configuration: configuration)",
            "feedPropagationAttemptLimit = 6",
            "if case .updateAvailable(let release) = result",
            "try await retryDelay()",
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
            "runner: macos-15",
            "runner: macos-15-intel",
            "runs-on: ${{ matrix.runner }}",
            "arch: arm64",
            "arch: x86_64",
            "needs: [publish, verify-published, promote-stable]",
            "needs.promote-stable.result == 'success'",
            "scripts/packaged-macos-updater-smoke.sh",
            "quillcode-public-updater-smoke-${{ matrix.arch }}"
        ])
    }
}
