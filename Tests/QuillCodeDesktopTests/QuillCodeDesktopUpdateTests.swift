import CryptoKit
import Darwin
import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdateModelTests: XCTestCase {
    func testReleaseDisplayVersionUsesStandardVersionAndBuildFormatting() {
        XCTAssertEqual(makeRelease(version: "0.2.0", build: "7").displayVersion, "0.2.0 (7)")
    }

    func testSemanticVersionOrderingHandlesBuildMetadataAndPrereleases() throws {
        XCTAssertLessThan(try version("0.9.9"), try version("1.0.0-alpha.1"))
        XCTAssertLessThan(try version("1.0.0-alpha.1"), try version("1.0.0-alpha.beta"))
        XCTAssertLessThan(try version("1.0.0-alpha.beta"), try version("1.0.0-beta"))
        XCTAssertLessThan(try version("1.0.0-beta.2"), try version("1.0.0-beta.11"))
        XCTAssertLessThan(try version("1.0.0-rc.1"), try version("1.0.0"))
        XCTAssertEqual(try version("1.0"), try version("1.0.0+build.7"))
        XCTAssertNil(QuillCodeDesktopSemanticVersion("1..0"))
        XCTAssertNil(QuillCodeDesktopSemanticVersion("01.0.0"))
    }

    func testValidatorSelectsOnlyANewerMatchingApplication() throws {
        let configuration = makeConfiguration(currentVersion: "0.1.0", currentBuild: "41")

        XCTAssertEqual(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                makeManifest(version: "0.1.0", build: "42"),
                configuration: configuration
            ),
            .updateAvailable(makeRelease(version: "0.1.0", build: "42"))
        )
        XCTAssertEqual(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                makeManifest(version: "0.1.0", build: "41"),
                configuration: configuration
            ),
            .upToDate(latestVersion: "0.1.0", latestBuild: "41")
        )
        XCTAssertEqual(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                makeManifest(version: "0.0.9", build: "999"),
                configuration: configuration
            ),
            .upToDate(latestVersion: "0.0.9", latestBuild: "999")
        )
    }

    func testValidatorRejectsWrongArchitectureAndRepository() throws {
        let configuration = makeConfiguration()
        var wrongArchitecture = makeManifest()
        wrongArchitecture.updater.macOSAppAsset?.arch = "x86_64"
        wrongArchitecture.assets[0].arch = "x86_64"

        XCTAssertThrowsError(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                wrongArchitecture,
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .noCompatibleApplication)
        }

        var wrongRepository = makeManifest()
        let hostileURL = try XCTUnwrap(URL(
            string: "https://github.com/Elsewhere/Other/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip"
        ))
        wrongRepository.updater.macOSAppAsset?.url = hostileURL
        wrongRepository.assets[0].url = hostileURL

        XCTAssertThrowsError(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                wrongRepository,
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .noCompatibleApplication)
        }
    }

    func testCheckerDecodesAndValidatesManifestData() async throws {
        let data = try JSONEncoder().encode(makeManifest(version: "0.2.0", build: "1"))
        let checker = QuillCodeDesktopUpdateChecker(loader: UpdateManifestLoaderStub(data: data))

        let result = try await checker.check(configuration: makeConfiguration())

        XCTAssertEqual(result, .updateAvailable(makeRelease(version: "0.2.0", build: "1")))
    }

    func testArchiveVerificationRejectsTampering() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("update.zip")
        try Data("payload".utf8).write(to: archive)

        try QuillCodeDesktopUpdatePreparer.verifyArchive(
            at: archive,
            expectedSize: 7,
            expectedSHA256: "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5"
        )
        XCTAssertThrowsError(
            try QuillCodeDesktopUpdatePreparer.verifyArchive(
                at: archive,
                expectedSize: 7,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        ) { error in
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .checksumMismatch)
        }
    }

    func testPreparerPrunesPreviousUpdateWorkspaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staleWorkspace = root.appendingPathComponent("old-build", isDirectory: true)
        let staleFile = root.appendingPathComponent("partial-download.zip")
        try FileManager.default.createDirectory(at: staleWorkspace, withIntermediateDirectories: false)
        try Data("partial".utf8).write(to: staleFile)
        let preparer = QuillCodeDesktopUpdatePreparer(cacheRoot: root)
        let release = makeRelease(build: "617")

        let workspace = try await preparer.makeCleanWorkspace(for: release)

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleWorkspace.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path),
            [workspace.lastPathComponent]
        )
    }

    func testRecoveryRemovesOnlyOwnedStagingApplicationDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationURL = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        try makeFakeApplication(
            at: applicationURL,
            version: "0.1.0",
            build: "42",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let validIdentifier = UUID().uuidString.lowercased()
        let stagingURL = root.appendingPathComponent(
            ".Quill Cowork.update-\(validIdentifier).app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        let malformedURL = root.appendingPathComponent(
            ".Quill Cowork.update-not-a-uuid.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: malformedURL, withIntermediateDirectories: false)
        let otherApplicationURL = root.appendingPathComponent(
            ".Other App.update-\(UUID().uuidString.lowercased()).app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: otherApplicationURL,
            withIntermediateDirectories: false
        )
        let symlinkTargetURL = root.appendingPathComponent("symlink-target", isDirectory: true)
        try FileManager.default.createDirectory(at: symlinkTargetURL, withIntermediateDirectories: false)
        let symlinkURL = root.appendingPathComponent(
            ".Quill Cowork.update-\(UUID().uuidString.lowercased()).app",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: symlinkTargetURL)

        let removed = try QuillCodeDesktopUpdateRecovery.removeOrphanedStagingApplications(
            beside: applicationURL,
            bundleIdentifier: "co.lorehex.QuillCowork"
        )

        XCTAssertEqual(removed.map(\.lastPathComponent), [stagingURL.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherApplicationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkTargetURL.path))
    }

    func testRecoveryRefusesToCleanBesideUnexpectedApplicationIdentity() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationURL = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        try makeFakeApplication(
            at: applicationURL,
            version: "0.1.0",
            build: "42",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let stagingURL = root.appendingPathComponent(
            ".Quill Cowork.update-\(UUID().uuidString.lowercased()).app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)

        let removed = try QuillCodeDesktopUpdateRecovery.removeOrphanedStagingApplications(
            beside: applicationURL,
            bundleIdentifier: "com.example.NotQuillCowork"
        )

        XCTAssertEqual(removed, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testRecoveryCancellationDuringGracePeriodLeavesStagingUntouched() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationURL = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        try makeFakeApplication(
            at: applicationURL,
            version: "0.1.0",
            build: "42",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        let stagingURL = root.appendingPathComponent(
            ".Quill Cowork.update-\(UUID().uuidString.lowercased()).app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        var configuration = makeConfiguration()
        configuration.applicationURL = applicationURL
        let recovery = QuillCodeDesktopUpdateRecovery(gracePeriod: 60)
        let task = Task {
            await recovery.recoverInterruptedUpdate(configuration: configuration)
        }

        task.cancel()
        await task.value

        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testPreparerRemovesWorkspaceAfterDownloadFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preparer = QuillCodeDesktopUpdatePreparer(
            downloader: FailingUpdateDownloader(error: .invalidResponse),
            cacheRoot: root
        )

        do {
            _ = try await preparer.prepare(
                release: makeRelease(build: "618"),
                configuration: makeConfiguration()
            )
            XCTFail("Expected updater preparation to fail")
        } catch {
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .invalidResponse)
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testPreparerRemovesWorkspaceAfterCancellation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preparer = QuillCodeDesktopUpdatePreparer(
            downloader: CancellingUpdateDownloader(),
            cacheRoot: root
        )

        do {
            _ = try await preparer.prepare(
                release: makeRelease(build: "619"),
                configuration: makeConfiguration()
            )
            XCTFail("Expected updater preparation to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testHelperArgumentsRoundTripWithoutInterpretingPathsAsShell() throws {
        let root = URL(fileURLWithPath: "/tmp/Quill Cowork update; untouched")
        let request = QuillCodeDesktopUpdateHelperRequest(
            parentProcessID: 123,
            helperURL: root.appendingPathComponent("helper"),
            incomingApplicationURL: root.appendingPathComponent(".Quill Cowork.update-id.app"),
            destinationApplicationURL: root.appendingPathComponent("Quill Cowork.app"),
            handshakeURL: root.appendingPathComponent("launch-id.ack"),
            resultURL: root.appendingPathComponent("UpdateResult.json"),
            logURL: root.appendingPathComponent("install.log"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork",
            expectedVersion: "0.2.0",
            expectedBuild: "99"
        )

        let parsed = try XCTUnwrap(QuillCodeDesktopUpdateHelperRequest.parse(
            arguments: ["helper"] + request.arguments,
            executableURL: request.helperURL
        ))

        XCTAssertEqual(parsed.parentProcessID, request.parentProcessID)
        XCTAssertEqual(parsed.incomingApplicationURL, request.incomingApplicationURL)
        XCTAssertEqual(parsed.destinationApplicationURL, request.destinationApplicationURL)
        XCTAssertEqual(parsed.handshakeURL, request.handshakeURL)
        XCTAssertEqual(parsed.resultURL, request.resultURL)
        XCTAssertEqual(parsed.logURL, request.logURL)
        XCTAssertEqual(parsed.expectedVersion, request.expectedVersion)
        XCTAssertEqual(parsed.expectedBuild, request.expectedBuild)
    }

    func testHelperCompletesVerifiedSwapAfterLaunchHandshake() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let workspace = cacheRoot.appendingPathComponent("success-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        try Data("staged".utf8).write(to: workspace.appendingPathComponent("archive.zip"))
        let destination = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        let incoming = root.appendingPathComponent(".Quill Cowork.update-success.app", isDirectory: true)
        try makeFakeApplication(
            at: destination,
            version: "0.1.0",
            build: "1",
            executableScript: "#!/bin/sh\nexit 0\n"
        )
        try makeFakeApplication(
            at: incoming,
            version: "0.2.0",
            build: "2",
            executableScript: """
            #!/bin/sh
            if [ "$1" = "--quillcode-update-handshake" ] && [ -n "$2" ]; then
              printf 'ready\n' > "$2"
            fi
            exit 0
            """
        )
        let resultURL = root.appendingPathComponent("UpdateResult.json")
        let request = makeHelperRequest(
            cacheRoot: cacheRoot,
            destination: destination,
            incoming: incoming,
            resultURL: resultURL,
            expectedVersion: "0.2.0",
            expectedBuild: "2",
            suffix: "success",
            workspace: workspace
        )
        let environment = QuillCodeDesktopUpdateHelperEnvironment(
            cacheRootURL: cacheRoot,
            resultURL: resultURL,
            parentExitTimeout: 0.1,
            launchHandshakeTimeout: 2
        )

        let parsedRequest = try XCTUnwrap(QuillCodeDesktopUpdateHelperRequest.parse(
            arguments: [request.helperURL.path] + request.arguments,
            executableURL: request.helperURL
        ))

        XCTAssertEqual(QuillCodeDesktopUpdateHelper.run(parsedRequest, environment: environment), 0)
        XCTAssertEqual(try bundleBuild(at: destination), "2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
        let result = try JSONDecoder().decode(
            QuillCodeDesktopUpdateInstallResult.self,
            from: Data(contentsOf: resultURL)
        )
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.version, "0.2.0")
        XCTAssertEqual(result.build, "2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testHelperTerminatesFailedChildAndRollsBack() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let workspace = cacheRoot.appendingPathComponent("rollback-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let destination = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        let incoming = root.appendingPathComponent(".Quill Cowork.update-rollback.app", isDirectory: true)
        let childPIDURL = root.appendingPathComponent("failed-child.pid")
        let rollbackLaunchedURL = root.appendingPathComponent("rollback-launched")
        try makeFakeApplication(
            at: destination,
            version: "0.1.0",
            build: "1",
            executableScript: "#!/bin/sh\nprintf 'ready' > '\(rollbackLaunchedURL.path)'\nexit 0\n"
        )
        try makeFakeApplication(
            at: incoming,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/bin/sh\nprintf '%s' \"$$\" > '\(childPIDURL.path)'\nsleep 30\n"
        )
        let resultURL = root.appendingPathComponent("UpdateResult.json")
        let request = makeHelperRequest(
            cacheRoot: cacheRoot,
            destination: destination,
            incoming: incoming,
            resultURL: resultURL,
            expectedVersion: "0.2.0",
            expectedBuild: "2",
            suffix: "rollback",
            workspace: workspace
        )
        let environment = QuillCodeDesktopUpdateHelperEnvironment(
            cacheRootURL: cacheRoot,
            resultURL: resultURL,
            parentExitTimeout: 0.1,
            launchHandshakeTimeout: 1
        )

        XCTAssertEqual(QuillCodeDesktopUpdateHelper.run(request, environment: environment), 1)
        XCTAssertEqual(try bundleBuild(at: destination), "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
        let childPID = try XCTUnwrap(Int32(String(contentsOf: childPIDURL, encoding: .utf8)))
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        let result = try JSONDecoder().decode(
            QuillCodeDesktopUpdateInstallResult.self,
            from: Data(contentsOf: resultURL)
        )
        XCTAssertEqual(result.status, .failure)
        XCTAssertTrue(result.message.contains("previous build was restored"))
        let rollbackDeadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: rollbackLaunchedURL.path),
              Date() < rollbackDeadline {
            usleep(10_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackLaunchedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testHelperRollsBackWhenUpdatedExecutableCannotLaunch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let workspace = cacheRoot.appendingPathComponent("launch-failure-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let destination = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        let incoming = root.appendingPathComponent(".Quill Cowork.update-launch-failure.app", isDirectory: true)
        let rollbackLaunchedURL = root.appendingPathComponent("rollback-launched")
        try makeFakeApplication(
            at: destination,
            version: "0.1.0",
            build: "1",
            executableScript: "#!/bin/sh\nprintf 'ready' > '\(rollbackLaunchedURL.path)'\nexit 0\n"
        )
        try makeFakeApplication(
            at: incoming,
            version: "0.2.0",
            build: "2",
            executableScript: "#!/definitely/missing/interpreter\n"
        )
        let resultURL = root.appendingPathComponent("UpdateResult.json")
        let request = makeHelperRequest(
            cacheRoot: cacheRoot,
            destination: destination,
            incoming: incoming,
            resultURL: resultURL,
            expectedVersion: "0.2.0",
            expectedBuild: "2",
            suffix: "launch-failure",
            workspace: workspace
        )
        let environment = QuillCodeDesktopUpdateHelperEnvironment(
            cacheRootURL: cacheRoot,
            resultURL: resultURL,
            parentExitTimeout: 0.1,
            launchHandshakeTimeout: 0.1
        )

        XCTAssertEqual(QuillCodeDesktopUpdateHelper.run(request, environment: environment), 1)
        XCTAssertEqual(try bundleBuild(at: destination), "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
        let result = try JSONDecoder().decode(
            QuillCodeDesktopUpdateInstallResult.self,
            from: Data(contentsOf: resultURL)
        )
        XCTAssertEqual(result.status, .failure)
        XCTAssertTrue(result.message.contains("previous build was restored"))
        let rollbackDeadline = Date().addingTimeInterval(1)
        while !FileManager.default.fileExists(atPath: rollbackLaunchedURL.path),
              Date() < rollbackDeadline {
            usleep(10_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackLaunchedURL.path))
    }

    func testBundledConfigurationReadsEveryReleaseFeedKey() throws {
        let bundle = try makeApplicationBundle()

        let configuration = try XCTUnwrap(
            QuillCodeDesktopUpdateConfiguration.bundled(bundle: bundle, architecture: "arm64")
        )

        XCTAssertEqual(configuration.channel, .tester)
        XCTAssertEqual(configuration.currentVersion, "0.1.0")
        XCTAssertEqual(configuration.currentBuild, "42")
        XCTAssertEqual(configuration.bundleIdentifier, "co.lorehex.QuillCowork")
        XCTAssertEqual(configuration.architecture, "arm64")
        XCTAssertEqual(configuration.expectedSigningTeamIdentifier, "ABCD123456")
    }

    private func version(_ value: String) throws -> QuillCodeDesktopSemanticVersion {
        try XCTUnwrap(QuillCodeDesktopSemanticVersion(value))
    }

    private func makeHelperRequest(
        cacheRoot: URL,
        destination: URL,
        incoming: URL,
        resultURL: URL,
        expectedVersion: String,
        expectedBuild: String,
        suffix: String,
        workspace: URL? = nil
    ) -> QuillCodeDesktopUpdateHelperRequest {
        let workspace = workspace ?? cacheRoot
        return QuillCodeDesktopUpdateHelperRequest(
            parentProcessID: Int32.max,
            helperURL: workspace.appendingPathComponent("helper"),
            incomingApplicationURL: incoming,
            destinationApplicationURL: destination,
            handshakeURL: workspace.appendingPathComponent("launch-\(suffix).ack"),
            resultURL: resultURL,
            logURL: workspace.appendingPathComponent("install.log"),
            expectedBundleIdentifier: "co.lorehex.QuillCowork",
            expectedVersion: expectedVersion,
            expectedBuild: expectedBuild
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func bundleBuild(at applicationURL: URL) throws -> String {
        let infoURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        return try XCTUnwrap(values["CFBundleVersion"] as? String)
    }
}

private struct UpdateManifestLoaderStub: QuillCodeDesktopUpdateManifestLoading {
    var data: Data

    func loadManifest(from url: URL, byteLimit: Int) async throws -> Data {
        guard data.count <= byteLimit else { throw QuillCodeDesktopUpdateError.manifestTooLarge }
        return data
    }
}

private struct FailingUpdateDownloader: QuillCodeDesktopUpdateDownloading {
    var error: QuillCodeDesktopUpdateError

    func download(from url: URL, to destinationURL: URL, maximumBytes: Int64) async throws {
        throw error
    }
}

private struct CancellingUpdateDownloader: QuillCodeDesktopUpdateDownloading {
    func download(from url: URL, to destinationURL: URL, maximumBytes: Int64) async throws {
        throw CancellationError()
    }
}

func makeConfiguration(
    currentVersion: String = "0.1.0",
    currentBuild: String = "42"
) -> QuillCodeDesktopUpdateConfiguration {
    QuillCodeDesktopUpdateConfiguration(
        channel: .tester,
        manifestURL: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
        )!,
        stableManifestURL: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json"
        )!,
        testerManifestURL: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
        )!,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        bundleIdentifier: "co.lorehex.QuillCowork",
        architecture: "arm64",
        applicationURL: URL(fileURLWithPath: "/Applications/Quill Cowork.app"),
        expectedSigningTeamIdentifier: nil
    )
}

private func makeManifest(
    version: String = "0.1.0",
    build: String = "43"
) -> QuillCodeDesktopUpdateManifest {
    let asset = makeAsset()
    return QuillCodeDesktopUpdateManifest(
        schemaVersion: 1,
        product: "Quill Cowork",
        channel: .tester,
        tag: "tester-latest",
        releaseURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest")!,
        commit: String(repeating: "a", count: 40),
        version: version,
        build: build,
        generatedAt: "2026-08-06T00:00:00Z",
        workflowRunURL: URL(string: "https://github.com/Lore-Hex/QuillCode/actions/runs/1")!,
        updater: .init(
            schemaVersion: 1,
            format: "github-release-manifest",
            channel: .tester,
            manifestURL: URL(
                string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
            )!,
            stableManifestURL: URL(
                string: "https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json"
            )!,
            testerManifestURL: URL(
                string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
            )!,
            bundleIdentifier: "co.lorehex.QuillCowork",
            minimumSystemVersion: "14.0",
            codesign: "ad-hoc",
            signingTeamIdentifier: nil,
            notarized: false,
            macOSAppAsset: asset
        ),
        assets: [asset]
    )
}

func makeRelease(
    version: String = "0.1.0",
    build: String = "43"
) -> QuillCodeDesktopUpdateRelease {
    QuillCodeDesktopUpdateRelease(
        channel: .tester,
        tag: "tester-latest",
        releaseURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest")!,
        commit: String(repeating: "a", count: 40),
        version: version,
        build: build,
        asset: makeAsset()
    )
}

private func makeAsset() -> QuillCodeDesktopUpdateManifest.Asset {
    QuillCodeDesktopUpdateManifest.Asset(
        name: "Quill-Cowork-macOS-arm64.zip",
        kind: "app",
        platform: "macOS",
        arch: "arm64",
        install: "zip-app",
        sizeBytes: 10_000,
        sha256: String(repeating: "b", count: 64),
        url: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip"
        )!
    )
}

private func makeApplicationBundle() throws -> Bundle {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("Quill Cowork.app", isDirectory: true)
    let contents = root.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    let executable = executableDirectory.appendingPathComponent("Quill Cowork")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let plist: [String: Any] = [
        "CFBundleExecutable": "Quill Cowork",
        "CFBundleIdentifier": "co.lorehex.QuillCowork",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "42",
        "QuillCodeUpdateChannel": "tester",
        "QuillCodeUpdateManifestURL": "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json",
        "QuillCodeStableUpdateManifestURL": "https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json",
        "QuillCodeTesterUpdateManifestURL": "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json",
        "QuillCodeSigningTeamIdentifier": "ABCD123456"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return try XCTUnwrap(Bundle(url: root))
}

private func makeFakeApplication(
    at root: URL,
    version: String,
    build: String,
    executableScript: String
) throws {
    let contents = root.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    let executable = executableDirectory.appendingPathComponent("Quill Cowork")
    try Data(executableScript.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let plist: [String: Any] = [
        "CFBundleExecutable": "Quill Cowork",
        "CFBundleIdentifier": "co.lorehex.QuillCowork",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}
