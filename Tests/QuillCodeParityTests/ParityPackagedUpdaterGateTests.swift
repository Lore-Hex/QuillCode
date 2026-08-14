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
        let helper = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateHelper.swift"
        )
        let installer = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateInstaller.swift"
        )
        let transaction = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateTransaction.swift"
        )
        let recovery = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateRecovery.swift"
        )
        let launcher = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateApplicationLauncher.swift"
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
        Self.assertSource(helper, containsAll: [
            "QuillCodeDesktopUpdateApplicationLauncher.launch(",
            "QuillCodeDesktopUpdateTransaction.validate(",
            "applicationLaunchMode: .launchServices"
        ])
        Self.assertSource(installer, containsAll: [
            "QuillCodeDesktopUpdateTransaction.persist(",
            "QuillCodeDesktopUpdateTransaction.discardUnactivated(",
            "QuillCodeDesktopUpdateHelperLauncher.launch(request)"
        ])
        Self.assertSource(transaction, containsAll: [
            "static let fileName = \"UpdateTransaction.json\"",
            "static let maximumEncodedBytes = 16 * 1_024",
            "options: [.atomic, .completeFileProtection]",
            "func hasValidRecoveryLayout(",
            "QuillCodeDesktopBuildMetadata.isCanonicalCommit(expectedCommit)",
            "static func discardUnactivated("
        ])
        Self.assertSource(recovery, containsAll: [
            "reconcileInterruptedTransactions(",
            "guard let protectedStaging",
            "let replacementIsRunning = destinationIdentity == expectedIdentity",
            "let destinationMatchesRunningBuild =",
            "let previousBuildIsRunning = destinationMatchesRunningBuild",
            "preserving: protectedStaging",
            "return nil"
        ])
        Self.assertSource(launcher, containsAll: [
            "NSWorkspace.shared.openApplication(",
            "configuration.activates = true",
            "configuration.createsNewApplicationInstance = true",
            "configuration.allowsRunningApplicationSubstitution = false",
            "configuration.arguments = arguments",
            "configuration.environment = ProcessInfo.processInfo.environment",
            "processIdentifier: application.processIdentifier",
            "isRunning: { !application.isTerminated }"
        ])
        Self.assertSource(runner, containsAll: [
            "--updater-smoke-manifest",
            "QuillCodeDesktopUpdaterSmokeManifestLoader",
            "values.isRegularFile == true",
            "values.isSymbolicLink != true",
            "read(upToCount: byteLimit + 1)",
            "loader: QuillCodeDesktopUpdaterSmokeManifestLoader(manifestURL: manifestURL)",
            "candidateUpdate(",
            "the verified candidate manifest did not advance beyond the smoke fixture",
            "QuillCodeDesktopUpdatePreparer().prepare",
            "QuillCodeDesktopUpdateInstaller().stageAndLaunch",
            "targetCommit: release.commit"
        ])
        Self.assertSource(script, containsAll: [
            "--native-updater-smoke",
            "--updater-smoke-report",
            "--updater-smoke-manifest \"$MANIFEST_PATH\"",
            "--source-manifest",
            "SOURCE_MODE=\"previous-public-build\"",
            "SOURCE_MODE=\"synthetic-first-release\"",
            "install-result.json",
            "install-helper.log",
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
            "needs: [macos, macos-universal, linux, capture-updater-source]",
            "verify-updater:",
            "runner: macos-15",
            "runner: macos-15-intel",
            "runs-on: ${{ matrix.runner }}",
            "arch: arm64",
            "arch: x86_64",
            "needs: [publish, verify-published, capture-updater-source]",
            "needs.capture-updater-source.result == 'success'",
            "needs: [publish, verify-published, verify-updater]",
            "needs.verify-updater.result == 'success'",
            "sourceAvailable raw",
            "--source-manifest \"$CAPTURE_DIR/source-manifest.json\"",
            "Quill-Cowork-macOS-universal.dmg",
            "Verify universal installer launches natively",
            "--expected-architecture '${{ matrix.arch }}'",
            "scripts/packaged-macos-updater-smoke.sh",
            "quillcode-public-updater-smoke-${{ matrix.arch }}"
        ])
        let updaterIndex = try XCTUnwrap(workflow.range(of: "  verify-updater:"))
        let promotionIndex = try XCTUnwrap(workflow.range(of: "  promote-stable:"))
        XCTAssertLessThan(
            updaterIndex.lowerBound,
            promotionIndex.lowerBound,
            "stable candidates must prove updater activation before becoming latest stable"
        )
    }
}
