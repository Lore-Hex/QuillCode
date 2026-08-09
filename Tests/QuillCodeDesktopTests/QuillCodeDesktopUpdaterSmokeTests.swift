import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdaterSmokeTests: XCTestCase {
    func testRequestRequiresModeAndAbsoluteReportPath() throws {
        let request = try XCTUnwrap(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "/tmp/updater-smoke.json",
        ]))

        XCTAssertEqual(request.reportURL.path, "/tmp/updater-smoke.json")
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: ["Quill Cowork"]))
        XCTAssertNil(QuillCodeDesktopUpdaterSmokeRequest(arguments: [
            "Quill Cowork",
            "--native-updater-smoke",
            "--updater-smoke-report",
            "relative.json",
        ]))
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
    func testAvailableUpdateRetriesAStalePublishedFeed() async throws {
        let release = makeRelease()
        let checker = UpdaterSmokeCheckerStub(results: [
            .upToDate(latestVersion: "0.1.0", latestBuild: "680"),
            .upToDate(latestVersion: "0.1.0", latestBuild: "680"),
            .updateAvailable(release),
        ])
        let delay = UpdaterSmokeRetryDelaySpy()

        let result = try await QuillCodeDesktopUpdaterSmokeRunner.waitForAvailableUpdate(
            configuration: makeConfiguration(),
            checker: checker,
            retryDelay: { await delay.record() }
        )

        XCTAssertEqual(result, release)
        let checkCallCount = await checker.callCount
        let delayCallCount = await delay.callCount
        XCTAssertEqual(checkCallCount, 3)
        XCTAssertEqual(delayCallCount, 2)
    }

    @MainActor
    func testAvailableUpdateFailsAfterBoundedStaleFeedRetries() async throws {
        let checker = UpdaterSmokeCheckerStub(results: [
            .upToDate(latestVersion: "0.1.0", latestBuild: "680"),
        ])
        let delay = UpdaterSmokeRetryDelaySpy()

        do {
            _ = try await QuillCodeDesktopUpdaterSmokeRunner.waitForAvailableUpdate(
                configuration: makeConfiguration(),
                checker: checker,
                retryDelay: { await delay.record() }
            )
            XCTFail("Expected a stale feed to fail after bounded retries")
        } catch {
            XCTAssertEqual(
                error as? QuillCodeDesktopUpdateError,
                .installationFailed(
                    "the published update feed did not advance beyond the smoke fixture after bounded retries"
                )
            )
        }

        let checkCallCount = await checker.callCount
        let delayCallCount = await delay.callCount
        XCTAssertEqual(checkCallCount, QuillCodeDesktopUpdaterSmokeRunner.feedPropagationAttemptLimit)
        XCTAssertEqual(delayCallCount, QuillCodeDesktopUpdaterSmokeRunner.feedPropagationAttemptLimit - 1)
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
    private var results: [QuillCodeDesktopUpdateCheckResult]
    private(set) var callCount = 0

    init(results: [QuillCodeDesktopUpdateCheckResult]) {
        self.results = results
    }

    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult {
        callCount += 1
        guard let result = results.first else {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        if results.count > 1 {
            results.removeFirst()
        }
        return result
    }
}

private actor UpdaterSmokeRetryDelaySpy {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}
