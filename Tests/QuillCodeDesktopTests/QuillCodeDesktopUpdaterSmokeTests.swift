import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdaterSmokeTests: XCTestCase {
    func testRequestRequiresModeAndAbsoluteReportAndManifestPaths() throws {
        let request = try XCTUnwrap(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "/tmp/updater-smoke.json",
            "--updater-smoke-manifest",
            "/tmp/latest-candidate-build.json",
        ]))

        XCTAssertEqual(request.reportURL.path, "/tmp/updater-smoke.json")
        XCTAssertEqual(request.manifestURL.path, "/tmp/latest-candidate-build.json")
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: ["Quill Cowork"]))
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "relative.json",
            "--updater-smoke-manifest",
            "/tmp/latest-candidate-build.json",
        ]))
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "/tmp/updater-smoke.json",
            "--updater-smoke-manifest",
            "relative.json",
        ]))
    }

    func testRequestRejectsMissingOrAmbiguousManifestFixture() {
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "/tmp/updater-smoke.json",
        ]))
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "/tmp/updater-smoke.json",
            "--updater-smoke-manifest",
            "/tmp/first.json",
            "--updater-smoke-manifest",
            "/tmp/second.json",
        ]))
    }

    func testFixtureManifestLoaderReadsOnlyBoundedRegularFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-updater-smoke-loader")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = root.appendingPathComponent("manifest.json")
        let payload = Data(#"{"build":"731"}"#.utf8)
        try payload.write(to: fixture)
        let loader = QuillCodeDesktopUpdaterSmokeManifestLoader(manifestURL: fixture)

        let loaded = try await loader.loadManifest(
            from: URL(string: "https://example.com/ignored.json")!,
            byteLimit: payload.count
        )

        XCTAssertEqual(loaded, payload)
    }

    func testFixtureManifestLoaderRejectsOversizedSymlinkAndMissingInputs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-updater-smoke-loader")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = root.appendingPathComponent("manifest.json")
        try Data("candidate".utf8).write(to: fixture)
        let symlink = root.appendingPathComponent("manifest-link.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: fixture)

        await assertLoaderError(
            QuillCodeDesktopUpdaterSmokeManifestLoader(manifestURL: fixture),
            byteLimit: 4,
            expected: .manifestTooLarge
        )
        await assertLoaderError(
            QuillCodeDesktopUpdaterSmokeManifestLoader(manifestURL: symlink),
            byteLimit: 32,
            expected: .invalidResponse
        )
        await assertLoaderError(
            QuillCodeDesktopUpdaterSmokeManifestLoader(
                manifestURL: root.appendingPathComponent("missing.json")
            ),
            byteLimit: 32,
            expected: .invalidResponse
        )
    }

    func testReportEncodesReleaseProvenance() throws {
        let report = QuillCodeDesktopUpdaterSmokeReport(
            ok: true,
            sourceVersion: "0.1.0",
            sourceBuild: "642",
            targetVersion: "0.1.0",
            targetBuild: "643",
            targetCommit: String(repeating: "a", count: 40),
            message: "staged"
        )

        let decoded = try JSONDecoder().decode(
            QuillCodeDesktopUpdaterSmokeReport.self,
            from: JSONEncoder().encode(report)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testCandidateUpdateReturnsAnAvailableRelease() async throws {
        let release = makeRelease()
        let checker = UpdaterSmokeCheckerStub(result: .updateAvailable(release))

        let result = try await QuillCodeDesktopUpdaterSmokeRunner.candidateUpdate(
            configuration: makeConfiguration(),
            checker: checker
        )

        XCTAssertEqual(result, release)
        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 1)
    }

    @MainActor
    func testCandidateUpdateRejectsANonadvancingFixtureWithoutRetrying() async throws {
        let checker = UpdaterSmokeCheckerStub(
            result: .upToDate(latestVersion: "0.1.0", latestBuild: "680")
        )

        do {
            _ = try await QuillCodeDesktopUpdaterSmokeRunner.candidateUpdate(
                configuration: makeConfiguration(),
                checker: checker
            )
            XCTFail("Expected a nonadvancing candidate fixture to fail")
        } catch {
            XCTAssertEqual(
                error as? QuillCodeDesktopUpdateError,
                .installationFailed(
                    "the verified candidate manifest did not advance beyond the smoke fixture"
                )
            )
        }

        let checkCallCount = await checker.callCount
        XCTAssertEqual(checkCallCount, 1)
    }

    private func makeConfiguration() -> QuillCodeDesktopUpdateConfiguration {
        QuillCodeDesktopUpdateConfiguration(
            channel: .tester,
            manifestURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json")!,
            stableManifestURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json")!,
            testerManifestURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json")!,
            currentVersion: "0.1.0",
            currentBuild: "680",
            bundleIdentifier: "co.lorehex.QuillCowork",
            architecture: "arm64",
            applicationURL: URL(fileURLWithPath: "/Applications/Quill Cowork.app"),
            expectedSigningTeamIdentifier: nil
        )
    }

    private func assertLoaderError(
        _ loader: QuillCodeDesktopUpdaterSmokeManifestLoader,
        byteLimit: Int,
        expected: QuillCodeDesktopUpdateError
    ) async {
        do {
            _ = try await loader.loadManifest(
                from: URL(string: "https://example.com/ignored.json")!,
                byteLimit: byteLimit
            )
            XCTFail("Expected fixture loader to fail with \(expected)")
        } catch {
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, expected)
        }
    }

    private func makeRelease() -> QuillCodeDesktopUpdateRelease {
        QuillCodeDesktopUpdateRelease(
            channel: .tester,
            tag: "tester-latest",
            releaseURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest")!,
            commit: String(repeating: "a", count: 40),
            version: "0.1.0",
            build: "681",
            asset: QuillCodeDesktopUpdateManifest.Asset(
                name: "Quill-Cowork-macOS-arm64.zip",
                kind: "app-zip",
                platform: "macOS",
                arch: "arm64",
                install: "Applications",
                sizeBytes: 1,
                sha256: String(repeating: "b", count: 64),
                url: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip")!
            ),
            signingRequirement: .adHoc
        )
    }
}

private actor UpdaterSmokeCheckerStub: QuillCodeDesktopUpdateChecking {
    private let result: QuillCodeDesktopUpdateCheckResult
    private(set) var callCount = 0

    init(result: QuillCodeDesktopUpdateCheckResult) {
        self.result = result
    }

    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult {
        callCount += 1
        return result
    }
}
