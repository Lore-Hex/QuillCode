import XCTest

final class ParityPackagedRelocationGateTests: QuillCodeParityTestCase {
    func testPublishedDMGMustProveTransactionalMoveAndRelaunch() throws {
        let app = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let controller = try Self.desktopSourceText(
            named: "QuillCodeDesktopInstallationLocationController.swift"
        )
        let relocator = try Self.desktopSourceText(
            named: "QuillCodeDesktopApplicationRelocator.swift"
        )
        let helper = try Self.desktopSourceText(named: "QuillCodeDesktopUpdateHelper.swift")
        let launcher = try Self.desktopSourceText(
            named: "QuillCodeDesktopUpdateApplicationLauncher.swift"
        )
        let runner = try Self.desktopSourceText(
            named: "QuillCodeDesktopRelocationSmokeRunner.swift"
        )
        let packageScript = try Self.scriptText(named: "package-macos-downloads.sh")
        let smokeScript = try Self.scriptText(named: "packaged-macos-relocation-smoke.sh")

        Self.assertSource(app, containsAll: [
            "QuillCodeDesktopRelocationSmokeRequest",
            "QuillCodeDesktopRelocationSmokeRunner.runAndExit"
        ])
        Self.assertSource(controller, containsAll: [
            "func moveAndRelaunch()",
            "hasOtherRunningCopy",
            "relocator.stageAndLaunch",
            "terminateApplication()"
        ])
        Self.assertSource(relocator, containsAll: [
            "QuillCodeDesktopDownloadedApplicationValidator.validate",
            "QuillCodeDesktopUpdateHelperLauncher.launch",
            "activationMode: destinationExists ? .replaceExisting : .installNew",
            "rollbackApplicationURL: destinationExists ? nil : sourceURL"
        ])
        Self.assertSource(helper, containsAll: [
            "case .installNew:",
            "try activate(request)",
            "UInt32(RENAME_EXCL)",
            ".isSymbolicLinkKey",
            "try fileManager.removeItem(at: request.destinationApplicationURL)",
            "QuillCodeDesktopUpdateApplicationLauncher.launch(",
            "rollbackApplicationURL,",
            "mode: environment.applicationLaunchMode"
        ])
        Self.assertSource(launcher, containsAll: [
            "NSWorkspace.shared.openApplication(",
            "configuration.createsNewApplicationInstance = true",
            "configuration.allowsRunningApplicationSubstitution = false"
        ])
        Self.assertSource(runner, containsAll: [
            "--native-relocation-smoke",
            "status: .helperLaunched",
            "QuillCodeDesktopSystemApplication.terminateForUpdate()"
        ])
        Self.assertSource(packageScript, containsAll: [
            "scripts/packaged-macos-relocation-smoke.sh",
            "--dmg \"$APP_DMG\"",
            "--expected-architecture \"$ARCH\""
        ])
        Self.assertSource(smokeScript, containsAll: [
            #""${TEMP_ROOT%/}/quill-cowork-relocation.XXXXXX""#,
            "hdiutil attach \"$DMG\" -readonly -nobrowse",
            "--relocation-smoke-applications \"$APPLICATIONS\"",
            "Installation helper reported failure",
            #"pgrep -f "$DESTINATION_EXECUTABLE --quillcode-update-handshake""#,
            #"kill "$DESTINATION_PID""#,
            #"kill -KILL "$DESTINATION_PID""#,
            "codesign --verify --deep --strict",
            "Relocated app identity does not match the mounted source"
        ])
    }
}
