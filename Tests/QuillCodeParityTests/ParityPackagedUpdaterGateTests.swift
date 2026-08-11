import XCTest

final class ParityPackagedUpdaterGateTests: QuillCodeParityTestCase {
    func testPublishedBuildMustUpdateAndRelaunchItself() throws {
        let app = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let controller = try Self.desktopControllerSourceText()
        let updateController = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateController.swift"
        )
        let updateSupport = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateSupport.swift"
        )
        let bootstrap = try Self.appSourceText(named: "WorkspaceBootstrap.swift")
        let runner = try Self.desktopSourceText(named: "QuillCodeDesktopUpdaterSmokeRunner.swift")
        let script = try Self.scriptText(named: "packaged-macos-updater-smoke.sh")
        let workflow = try Self.workflowText(named: "download-builds.yml")

        Self.assertSource(app, containsAll: [
            "_ = QuillCodeDesktopLaunchClock.appEntryUptime",
            "let updateLaunchHandshake = QuillCodeDesktopUpdateLaunchHandshake()",
            "updateLaunchHandshake: updateLaunchHandshake",
            "QuillCodeDesktopUpdaterSmokeRequest",
            "QuillCodeDesktopUpdaterSmokeRunner.runAndExit"
        ])
        XCTAssertFalse(app.contains(".acknowledge()"))
        let handshake = "let updateLaunchHandshake = QuillCodeDesktopUpdateLaunchHandshake()"
        XCTAssertEqual(app.components(separatedBy: handshake).count - 1, 1)
        let entryRange = try XCTUnwrap(app.range(of: "_ = QuillCodeDesktopLaunchClock.appEntryUptime"))
        let handshakeRange = try XCTUnwrap(app.range(of: handshake))
        let helperRange = try XCTUnwrap(app.range(of: "QuillCodeDesktopUpdateHelperRequest.parse"))
        XCTAssertLessThan(entryRange.lowerBound, handshakeRange.lowerBound)
        XCTAssertLessThan(handshakeRange.lowerBound, helperRange.lowerBound)
        XCTAssertFalse(app.contains("startApplicationServicesAfterFirstWindow"))
        XCTAssertFalse(app.contains("controller.updateController.startAutomaticChecks()"))
        XCTAssertFalse(app.contains("controller.installationLocationController.startIfNeeded()"))
        Self.assertSource(controller, containsAll: [
            "func startApplicationServicesAfterFirstWindow()",
            "func completeStartupIfAllowed()",
            "guard automaticStartupState.startPostWindowApplicationServicesIfNeeded() else { return }",
            "startApplicationServicesAfterFirstWindow()",
            "automaticStartupPolicy: .deferUntilRequested",
            "model.startAutomaticStartupWork()",
            "private func markLaunchReady()",
            "updateLaunchHandshake.acknowledge()",
            "self.updateLaunchHandshake = nil",
            "tasks.replace(.computerUseBackendResolution)",
            "startApplicationActivationObservation",
            "scheduleComputerUseStatusRefresh()",
            "installApprovalNotificationHandling()",
            "installationLocationController.startIfNeeded()",
            "updateController.startAutomaticChecks()"
        ])
        XCTAssertEqual(
            controller.components(separatedBy: "startApplicationServicesAfterFirstWindow()").count - 1,
            2
        )
        XCTAssertEqual(controller.components(separatedBy: "markLaunchReady()").count - 1, 4)
        Self.assertSource(updateSupport, containsAll: [
            "struct QuillCodeDesktopUpdateLaunchHandshake: Equatable, Sendable",
            "init?(arguments: [String] = CommandLine.arguments)",
            "func acknowledge() -> Bool",
            "Self.isAllowed(url, cacheRoot: cacheRoot)",
            "Data(\"ready\\n\".utf8).write"
        ])
        Self.assertSource(bootstrap, contains: "automaticStartupPolicy == .startImmediately")
        Self.assertSource(updateController, containsAll: [
            "let recoveryTask = cancelRecoveryAndTakeTask()",
            "await recoveryTask.value",
            "try Task.checkCancellation()",
            "guard self.generation == generation else { return }"
        ])
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
            "--source-manifest",
            "SOURCE_MODE=\"previous-public-build\"",
            "SOURCE_MODE=\"synthetic-first-release\"",
            "Previous public app metadata disagrees with its captured manifest.",
            "codesign --verify --deep --strict",
            "CFBundleVersion $SOURCE_BUILD",
            "sourceVersion",
            "targetCommit",
            "STAGING_APPS",
            "PUBLIC_APP_PARENT=\"${APP_PARENT#/private}\"",
            "kill -0 \"$UPDATED_PID\"",
            "Updated app did not remain running"
        ])
        Self.assertSource(workflow, containsAll: [
            "capture-updater-source:",
            "Capture previous public updater sources",
            "scripts/capture-public-updater-source.py",
            "name: quillcode-prior-updater-sources",
            "pattern: quillcode-*-downloads*",
            "needs: [macos, linux, capture-updater-source]",
            "verify-updater:",
            "runner: macos-15",
            "runner: macos-15-intel",
            "runs-on: ${{ matrix.runner }}",
            "arch: arm64",
            "arch: x86_64",
            "needs: [publish, verify-published, promote-stable, capture-updater-source]",
            "needs.capture-updater-source.result == 'success'",
            "needs.promote-stable.result == 'success'",
            "sourceAvailable raw",
            "--source-manifest \"$CAPTURE_DIR/source-manifest.json\"",
            "scripts/packaged-macos-updater-smoke.sh",
            "quillcode-public-updater-smoke-${{ matrix.arch }}"
        ])
    }
}
