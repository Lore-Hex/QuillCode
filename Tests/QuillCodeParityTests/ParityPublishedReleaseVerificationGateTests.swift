import CryptoKit
import Foundation
import XCTest

final class ParityPublishedReleaseVerificationGateTests: QuillCodeParityTestCase {
    private let repository = "Lore-Hex/QuillCode"
    private let tag = "tester-latest"
    private let commit = String(repeating: "a", count: 40)
    private let workflowRunURL = "https://github.com/Lore-Hex/QuillCode/actions/runs/12345"

    func testVerifierAcceptsAnExactPublishedReleaseSnapshot() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Verified public Quill Cowork tester release tester-latest"))
    }

    func testVerifierCanDiscoverPublishingRunFromExactManifest() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture, discoverWorkflowRunURL: true)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Verified public Quill Cowork tester release tester-latest"))
    }

    func testVerifierRejectsUnsafeDiscoveredPublishingRunURL() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try mutateManifest(fixture) { manifest in
            manifest["workflowRunURL"] = "https://example.com/actions/runs/12345"
        }

        let result = try runVerifier(fixture, discoverWorkflowRunURL: true)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("manifest publishing run URL is invalid"), result.output)
    }

    func testVerifierAcceptsAnExplicitStableCandidateBeforePromotion() throws {
        let fixture = try makeFixture(channel: "stable", prerelease: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture, stableCandidate: true)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Verified public Quill Cowork stable release v0.2.0"))
    }

    func testVerifierRejectsStableCandidateModeForTesterChannel() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture, stableCandidate: true)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("--stable-candidate requires --channel stable"),
            result.output
        )
    }

    func testVerifierRejectsStableCandidateUnderFinalReleaseRules() throws {
        let fixture = try makeFixture(channel: "stable", prerelease: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("prerelease state does not match its channel"),
            result.output
        )
    }

    func testVerifierAcceptsPromotedStableReleaseAndExactLatestFeed() throws {
        let fixture = try makeFixture(channel: "stable", prerelease: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Verified public Quill Cowork stable release v0.2.0"))
    }

    func testVerifierRejectsPromotedStableReleaseWhenLatestFeedDrifts() throws {
        let fixture = try makeFixture(channel: "stable", prerelease: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("{}\n".utf8).write(to: try XCTUnwrap(fixture.stableFeedManifest))

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("latest stable feed does not match"),
            result.output
        )
    }

    func testVerifierRejectsPromotedStableReleaseWhenLatestIdentityDrifts() throws {
        let fixture = try makeFixture(channel: "stable", prerelease: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let latestReleaseURL = try XCTUnwrap(fixture.latestReleaseJSON)
        var latestRelease = try jsonObject(at: latestReleaseURL)
        latestRelease["id"] = 54_321
        try writeJSON(latestRelease, to: latestReleaseURL)

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("latest release is not the verified stable release"),
            result.output
        )
    }

    func testVerifierRejectsPerformanceSchemaDriftAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            evidence["schemaVersion"] = 2
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance evidence schemaVersion is invalid"),
            result.output
        )
    }

    func testVerifierRejectsPerformanceWorkloadDriftAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            evidence["workload"] = "first-run-empty"
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance evidence workload is invalid"),
            result.output
        )
    }

    func testVerifierRejectsPerformanceMemoryMeasurementDriftAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            evidence["memoryMeasurement"] = "resident-set-size"
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance evidence memoryMeasurement is invalid"),
            result.output
        )
    }

    func testVerifierRejectsForgedPerformanceDeltaAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            var attempts = try XCTUnwrap(evidence["attempts"] as? [[String: Any]])
            attempts[2]["repeatedInteractionResidentMemoryGrowthBytes"] = 1
            evidence["attempts"] = attempts
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance attempt 3 repeated resident-memory delta is forged"),
            result.output
        )
    }

    func testVerifierRejectsForgedRetainedThreadDeltaAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            var attempts = try XCTUnwrap(evidence["attempts"] as? [[String: Any]])
            attempts[2]["repeatedInteractionRetainedThreadGrowth"] = 1
            evidence["attempts"] = attempts
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance attempt 3 repeated retained thread delta is forged"),
            result.output
        )
    }

    func testVerifierRecomputesPublishedPerformanceBudgetsAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            var attempts = try XCTUnwrap(evidence["attempts"] as? [[String: Any]])
            let postResident = try XCTUnwrap(
                attempts[2]["postInteractionResidentMemoryBytes"] as? Int
            )
            let repeatedGrowth = 17 * 1_024 * 1_024
            attempts[2]["repeatedInteractionResidentMemoryBytes"] = postResident + repeatedGrowth
            attempts[2]["repeatedInteractionResidentMemoryMiB"] = 119.0
            attempts[2]["repeatedInteractionResidentMemoryGrowthBytes"] = repeatedGrowth
            attempts[2]["repeatedInteractionResidentMemoryGrowthMiB"] = 17.0
            attempts[2]["idleResidentMemoryBytes"] = postResident + repeatedGrowth + 1 * 1_024 * 1_024
            attempts[2]["idleResidentMemoryMiB"] = 120.0
            evidence["attempts"] = attempts
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance attempt 3 violates the repeated resident-memory growth budget"),
            result.output
        )
    }

    func testVerifierRecomputesPublishedIdleCPUBudgetAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            var attempts = try XCTUnwrap(evidence["attempts"] as? [[String: Any]])
            attempts[2]["idleProcessorTimeNanoseconds"] = 400_000_000
            attempts[2]["idleProcessorTimeMilliseconds"] = 400.0
            attempts[2]["idleCPUPercent"] = 20.0
            evidence["attempts"] = attempts
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance attempt 3 violates the idle CPU budget"),
            result.output
        )
    }

    func testVerifierRejectsShortPublishedIdleMeasurement() throws {
        let fixture = try makeFixture { evidence in
            var attempts = try XCTUnwrap(evidence["attempts"] as? [[String: Any]])
            attempts[2]["idleDurationMilliseconds"] = 1_999.0
            attempts[2]["idleCPUPercent"] = 5.0025
            evidence["attempts"] = attempts
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance attempt 3 idle duration is too short"),
            result.output
        )
    }

    func testVerifierRejectsMissingPublishedPerformanceEvidence() throws {
        let fixture = try makeFixture(includePerformanceAsset: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains(
                "release must contain exactly one macOS performance for each architecture"
            ),
            result.output
        )
    }

    func testVerifierRejectsPublishedPerformancePolicyDriftAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture { evidence in
            var budgets = try XCTUnwrap(evidence["budgets"] as? [String: Any])
            budgets["maximumRepeatedResidentMemoryGrowthBytes"] = 32 * 1_024 * 1_024
            evidence["budgets"] = budgets
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("is not production policy"),
            result.output
        )
    }

    func testVerifierRejectsIncompletePublishedPerformanceAggregation() throws {
        let fixture = try makeFixture { evidence in
            var attempts = try XCTUnwrap(evidence["attempts"] as? [[String: Any]])
            attempts.removeLast()
            evidence["attempts"] = attempts
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("performance evidence must contain 3 attempts"),
            result.output
        )
    }

    func testVerifierRejectsPublishedPerformanceHeadlineDrift() throws {
        let fixture = try makeFixture { evidence in
            evidence["repeatedInteractionThreadGrowth"] = 1
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("disagrees with selectedAttempt"),
            result.output
        )
    }

    func testVerifierRejectsFeedDriftAndPayloadCorruption() throws {
        let feedFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: feedFixture.root) }
        try mutateManifest(feedFixture) { manifest in
            var updater = try XCTUnwrap(manifest["updater"] as? [String: Any])
            updater["manifestURL"] = stableManifestURL
            manifest["updater"] = updater
        }
        let feedResult = try runVerifier(feedFixture)
        XCTAssertEqual(feedResult.exitCode, 2, feedResult.output)
        XCTAssertTrue(feedResult.output.contains("updater manifestURL"), feedResult.output)

        let payloadFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: payloadFixture.root) }
        let appURL = payloadFixture.assets.appendingPathComponent("Quill-Cowork-macOS-arm64.zip")
        var appData = try Data(contentsOf: appURL)
        appData.append(Data("tampered".utf8))
        try appData.write(to: appURL)
        let payloadResult = try runVerifier(payloadFixture)
        XCTAssertEqual(payloadResult.exitCode, 2, payloadResult.output)
        XCTAssertTrue(payloadResult.output.contains("exceeds its declared size"), payloadResult.output)
    }

    func testVerifierRejectsStaleReleaseAssetsAndTagDrift() throws {
        let inventoryFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: inventoryFixture.root) }
        var release = try jsonObject(at: inventoryFixture.releaseJSON)
        var assets = try XCTUnwrap(release["assets"] as? [[String: Any]])
        assets.append([
            "name": "stale.zip",
            "state": "uploaded",
            "size": 1,
            "digest": "sha256:\(String(repeating: "0", count: 64))",
            "browser_download_url": releaseDownloadURL(named: "stale.zip")
        ])
        release["assets"] = assets
        try writeJSON(release, to: inventoryFixture.releaseJSON)
        let inventoryResult = try runVerifier(inventoryFixture)
        XCTAssertEqual(inventoryResult.exitCode, 2, inventoryResult.output)
        XCTAssertTrue(inventoryResult.output.contains("inventory does not exactly match"), inventoryResult.output)

        let tagFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: tagFixture.root) }
        let tagResult = try runVerifier(tagFixture, tagCommit: String(repeating: "b", count: 40))
        XCTAssertEqual(tagResult.exitCode, 2, tagResult.output)
        XCTAssertTrue(tagResult.output.contains("release tag resolves to"), tagResult.output)
    }

    func testVerifierRejectsReleaseNameThatDisagreesWithManifestIdentity() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var release = try jsonObject(at: fixture.releaseJSON)
        release["name"] = "Quill Cowork Tester 0.2.0 (124)"
        try writeJSON(release, to: fixture.releaseJSON)

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("release name does not match the manifest identity"),
            result.output
        )
    }

    func testVerifierRejectsAppArchiveCommitDriftAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture(appCommit: String(repeating: "b", count: 40))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("Info.plist QuillCodeBuildCommit disagrees with the manifest"),
            result.output
        )
    }

    func testVerifierRejectsSymlinkedAppInfoAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture(appInfoIsSymlink: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("Info.plist must be a readable regular entry"),
            result.output
        )
    }

    func testVerifierRejectsMislabeledIntelExecutableAfterIntegrityChecksPass() throws {
        let fixture = try makeFixture(intelExecutableArchitecture: "arm64")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("x86_64 app executable is not a thin x86_64 Mach-O"),
            result.output
        )
    }

    func testVerifierRejectsExecutableSizeThatDisagreesWithAppArchive() throws {
        let fixture = try makeFixture(armExecutableSizeBytes: 31)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("macOS app executable size disagrees with BUILD_INFO"),
            result.output
        )
    }

    func testVerifierRejectsIncompleteUpdaterArchitectureInventory() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try mutateManifest(fixture) { manifest in
            var updater = try XCTUnwrap(manifest["updater"] as? [String: Any])
            let legacyAsset = try XCTUnwrap(updater["macOSAppAsset"] as? [String: Any])
            updater["macOSAppAssets"] = [legacyAsset]
            manifest["updater"] = updater
        }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("must exactly cover arm64 and x86_64"),
            result.output
        )
    }

    func testVerifierRejectsUniversalInstallerMetadataDrift() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try mutateManifest(fixture) { manifest in
            var updater = try XCTUnwrap(manifest["updater"] as? [String: Any])
            updater.removeValue(forKey: "macOSUniversalInstaller")
            manifest["updater"] = updater
        }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("universal installer must match the published universal DMG"),
            result.output
        )
    }

    func testVerifierRejectsUnexpectedMacOSAppInstallMode() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try mutateManifest(fixture) { manifest in
            var assets = try XCTUnwrap(manifest["assets"] as? [[String: Any]])
            let index = try XCTUnwrap(assets.firstIndex {
                $0["name"] as? String == "Quill-Cowork-macOS-x86_64.zip"
            })
            assets[index]["install"] = "download"
            manifest["assets"] = assets
        }

        let result = try runVerifier(fixture)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.output.contains("macOS app assets must use zip-app installation"),
            result.output
        )
    }

    private struct Fixture {
        var root: URL
        var assets: URL
        var manifest: URL
        var releaseJSON: URL
        var latestReleaseJSON: URL?
        var stableFeedManifest: URL?
        var tag: String
        var channel: String
    }

    private func makeFixture(
        appCommit: String? = nil,
        appInfoIsSymlink: Bool = false,
        includePerformanceAsset: Bool = true,
        intelExecutableArchitecture: String = "x86_64",
        channel: String = "tester",
        prerelease: Bool? = nil,
        armExecutableSizeBytes: Int = 32,
        performanceMutation: ((inout [String: Any]) throws -> Void)? = nil
    ) throws -> Fixture {
        precondition(channel == "tester" || channel == "stable")
        let releaseTag = channel == "stable" ? "v0.2.0" : tag
        let updateManifestURL = channel == "stable" ? stableManifestURL : testerManifestURL
        let signingTeamIdentifier = channel == "stable" ? "A1B2C3D4E5" : nil
        let codesign = channel == "stable" ? "developer-id" : "ad-hoc"
        let notarized = channel == "stable"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-cowork-release-verifier-tests")
            .appendingPathComponent(UUID().uuidString)
        let assetsURL = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let buildInfoName = "BUILD_INFO.txt"
        let checksumsName = "SHASUMS256.txt"
        let architectures = ["arm64", "x86_64"]
        for architecture in architectures {
            let appName = "Quill-Cowork-macOS-\(architecture).zip"
            let installerName = "Quill-Cowork-macOS-\(architecture).dmg"
            let performanceName = "Quill-Cowork-macOS-\(architecture)-PERFORMANCE.json"
            let cliName = "quill-code-macOS-\(architecture).tar.gz"
            let executableArchitecture = architecture == "x86_64"
                ? intelExecutableArchitecture
                : architecture
            try writeAppArchive(
                to: assetsURL.appendingPathComponent(appName),
                commit: appCommit ?? commit,
                architecture: executableArchitecture,
                root: root,
                infoIsSymlink: appInfoIsSymlink,
                channel: channel,
                updateManifestURL: updateManifestURL,
                signingTeamIdentifier: signingTeamIdentifier
            )
            try Data("verified installer \(architecture)".utf8).write(
                to: assetsURL.appendingPathComponent(installerName)
            )
            try Data("verified cli \(architecture)".utf8).write(
                to: assetsURL.appendingPathComponent(cliName)
            )
            if includePerformanceAsset {
                var evidence = performanceEvidence()
                if architecture == "arm64" {
                    try performanceMutation?(&evidence)
                }
                try writeJSON(evidence, to: assetsURL.appendingPathComponent(performanceName))
            }
            let buildInfo = """
            product=Quill Cowork
            platform=macOS
            arch=\(architecture)
            version=0.2.0
            build=123
            commit=\(commit)
            createdAt=2026-08-07T00:00:00Z
            configuration=release
            symbolsStripped=true
            executableSizeBytes=\(architecture == "arm64" ? armExecutableSizeBytes : 32)
            bundleIdentifier=co.lorehex.QuillCowork
            minimumSystemVersion=14.0
            updateChannel=\(channel)
            updateManifestURL=\(updateManifestURL)
            stableUpdateManifestURL=\(stableManifestURL)
            testerUpdateManifestURL=\(testerManifestURL)
            installer=\(installerName)
            app=\(appName)
            performance=\(performanceName)
            cli=\(cliName)
            codesign=\(codesign)
            signingTeamIdentifier=\(signingTeamIdentifier ?? "none")
            notarized=\(notarized)
            """
            try buildInfo.write(
                to: assetsURL.appendingPathComponent("BUILD_INFO-macOS-\(architecture).txt"),
                atomically: true,
                encoding: .utf8
            )
            if architecture == "arm64" {
                try buildInfo.write(
                    to: assetsURL.appendingPathComponent(buildInfoName),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
        try Data("verified universal installer".utf8).write(
            to: assetsURL.appendingPathComponent("Quill-Cowork-macOS-universal.dmg")
        )

        var checksummedNames = try FileManager.default.contentsOfDirectory(
            atPath: assetsURL.path
        )
        checksummedNames.sort()
        let checksumText = try checksummedNames.map { name in
            let digest = try sha256(at: assetsURL.appendingPathComponent(name))
            return "\(digest)  \(name)"
        }.joined(separator: "\n") + "\n"
        try checksumText.write(
            to: assetsURL.appendingPathComponent(checksumsName),
            atomically: true,
            encoding: .utf8
        )

        var manifestAssets = try [
            manifestAsset(
                named: buildInfoName,
                kind: "metadata",
                platform: "macOS",
                arch: "any",
                install: "text",
                assetsURL: assetsURL,
                releaseTag: releaseTag
            )
        ]
        var appAssets: [[String: Any]] = []
        let universalInstallerAsset = try manifestAsset(
            named: "Quill-Cowork-macOS-universal.dmg",
            kind: "installer",
            platform: "macOS",
            arch: "universal",
            install: "dmg-app",
            assetsURL: assetsURL,
            releaseTag: releaseTag
        )
        manifestAssets.append(universalInstallerAsset)
        for architecture in architectures {
            manifestAssets.append(try manifestAsset(
                named: "BUILD_INFO-macOS-\(architecture).txt",
                kind: "metadata",
                platform: "macOS",
                arch: architecture,
                install: "text",
                assetsURL: assetsURL,
                releaseTag: releaseTag
            ))
            manifestAssets.append(try manifestAsset(
                named: "Quill-Cowork-macOS-\(architecture).dmg",
                kind: "installer",
                platform: "macOS",
                arch: architecture,
                install: "dmg-app",
                assetsURL: assetsURL,
                releaseTag: releaseTag
            ))
            let appAsset = try manifestAsset(
                named: "Quill-Cowork-macOS-\(architecture).zip",
                kind: "app",
                platform: "macOS",
                arch: architecture,
                install: "zip-app",
                assetsURL: assetsURL,
                releaseTag: releaseTag
            )
            appAssets.append(appAsset)
            manifestAssets.append(appAsset)
            if includePerformanceAsset {
                manifestAssets.append(try manifestAsset(
                    named: "Quill-Cowork-macOS-\(architecture)-PERFORMANCE.json",
                    kind: "performance",
                    platform: "macOS",
                    arch: architecture,
                    install: "json",
                    assetsURL: assetsURL,
                    releaseTag: releaseTag
                ))
            }
            manifestAssets.append(try manifestAsset(
                named: "quill-code-macOS-\(architecture).tar.gz",
                kind: "cli",
                platform: "macOS",
                arch: architecture,
                install: "tarball",
                assetsURL: assetsURL,
                releaseTag: releaseTag
            ))
        }
        manifestAssets.append(contentsOf: try [
            manifestAsset(
                named: checksumsName,
                kind: "checksum",
                platform: "any",
                arch: "any",
                install: "text",
                assetsURL: assetsURL,
                releaseTag: releaseTag
            )
        ])
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "product": "Quill Cowork",
            "channel": channel,
            "tag": releaseTag,
            "releaseURL": "https://github.com/\(repository)/releases/tag/\(releaseTag)",
            "commit": commit,
            "version": "0.2.0",
            "build": "123",
            "generatedAt": "2026-08-07T00:00:01Z",
            "workflowRunURL": workflowRunURL,
            "updater": [
                "schemaVersion": 1,
                "format": "github-release-manifest",
                "channel": channel,
                "manifestURL": updateManifestURL,
                "stableManifestURL": stableManifestURL,
                "testerManifestURL": testerManifestURL,
                "bundleIdentifier": "co.lorehex.QuillCowork",
                "minimumSystemVersion": "14.0",
                "codesign": codesign,
                "signingTeamIdentifier": signingTeamIdentifier.map { $0 as Any } ?? NSNull(),
                "notarized": notarized,
                "macOSUniversalInstaller": universalInstallerAsset,
                "macOSAppAsset": appAssets[0],
                "macOSAppAssets": appAssets
            ],
            "assets": manifestAssets
        ]
        let manifestURL = root.appendingPathComponent("latest-\(channel)-build.json")
        try writeJSON(manifest, to: manifestURL)

        var releaseAssets = try manifestAssets.map { asset -> [String: Any] in
            let name = try XCTUnwrap(asset["name"] as? String)
            return [
                "name": name,
                "state": "uploaded",
                "size": try XCTUnwrap(asset["sizeBytes"] as? Int),
                "digest": "sha256:\(try XCTUnwrap(asset["sha256"] as? String))",
                "browser_download_url": releaseDownloadURL(named: name, tag: releaseTag)
            ]
        }
        releaseAssets.append([
            "name": manifestURL.lastPathComponent,
            "state": "uploaded",
            "size": try Data(contentsOf: manifestURL).count,
            "digest": "sha256:\(try sha256(at: manifestURL))",
            "browser_download_url": releaseDownloadURL(
                named: manifestURL.lastPathComponent,
                tag: releaseTag
            )
        ])
        let release: [String: Any] = [
            "id": 12_345,
            "tag_name": releaseTag,
            "name": channel == "stable"
                ? "Quill Cowork \(releaseTag)"
                : "Quill Cowork Tester 0.2.0 (123)",
            "draft": false,
            "prerelease": prerelease ?? (channel == "tester"),
            "assets": releaseAssets
        ]
        let releaseJSONURL = root.appendingPathComponent("release.json")
        try writeJSON(release, to: releaseJSONURL)
        var latestReleaseJSON: URL?
        var stableFeedManifest: URL?
        if channel == "stable" {
            let latestURL = root.appendingPathComponent("latest-release.json")
            let feedURL = root.appendingPathComponent("latest-stable-feed.json")
            try writeJSON(release, to: latestURL)
            try Data(contentsOf: manifestURL).write(to: feedURL)
            latestReleaseJSON = latestURL
            stableFeedManifest = feedURL
        }
        return Fixture(
            root: root,
            assets: assetsURL,
            manifest: manifestURL,
            releaseJSON: releaseJSONURL,
            latestReleaseJSON: latestReleaseJSON,
            stableFeedManifest: stableFeedManifest,
            tag: releaseTag,
            channel: channel
        )
    }

    private func performanceEvidence() -> [String: Any] {
        let attempts = [
            performanceAttempt(
                number: 1,
                launchReadyMilliseconds: 3_100,
                residentMiB: 96,
                postInteractionMiB: 100,
                repeatedInteractionMiB: 102,
                threadCount: 18,
                postInteractionThreadCount: 20,
                repeatedInteractionThreadCount: 19
            ),
            performanceAttempt(
                number: 2,
                launchReadyMilliseconds: 500,
                residentMiB: 97,
                postInteractionMiB: 101,
                repeatedInteractionMiB: 103,
                threadCount: 19,
                postInteractionThreadCount: 20,
                repeatedInteractionThreadCount: 20
            ),
            performanceAttempt(
                number: 3,
                launchReadyMilliseconds: 400,
                residentMiB: 98,
                postInteractionMiB: 102,
                repeatedInteractionMiB: 104,
                threadCount: 20,
                postInteractionThreadCount: 21,
                repeatedInteractionThreadCount: 21
            )
        ]
        let selectedAttempt = attempts[1]
        var evidence: [String: Any] = [
            "schemaVersion": 7,
            "ok": true,
            "product": "Quill Cowork",
            "workload": "daily-driver-100-chats",
            "measurement": "initial-live-window",
            "memoryMeasurement": "physical-footprint",
            "processorTimeMeasurement": "process-user-plus-system-nanoseconds",
            "postInteractionMeasurement": "settled-after-native-interaction-sweep",
            "repeatedInteractionMeasurement": "settled-after-repeated-native-interaction-sweep",
            "idleMeasurement": "settled-idle-after-interaction-sweeps",
            "interactionSweepCount": 2,
            "aggregation": "median-of-fresh-processes",
            "attemptCount": 3,
            "selectedAttempt": 2,
            "passingAttemptCount": 2,
            "requiredPassingAttemptCount": 2,
            "attempts": attempts,
            "budgets": [
                "maximumLaunchReadyMilliseconds": 2_500.0,
                "maximumResidentMemoryBytes": 128 * 1_024 * 1_024,
                "maximumResidentMemoryGrowthBytes": 64 * 1_024 * 1_024,
                "maximumRepeatedResidentMemoryGrowthBytes": 16 * 1_024 * 1_024,
                "maximumThreadCount": 32,
                "maximumRepeatedRetainedThreadGrowth": 2,
                "maximumIdleCPUPercent": 5.0,
                "maximumIdleResidentMemoryGrowthBytes": 8 * 1_024 * 1_024,
                "maximumIdleThreadGrowth": 2
            ],
            "withinBudget": true
        ]
        let summaryFields = [
            "launchReadyMilliseconds",
            "residentMemoryBytes",
            "residentMemoryMiB",
            "threadCount",
            "postInteractionResidentMemoryBytes",
            "postInteractionResidentMemoryMiB",
            "postInteractionThreadCount",
            "residentMemoryGrowthBytes",
            "residentMemoryGrowthMiB",
            "threadGrowth",
            "repeatedInteractionResidentMemoryBytes",
            "repeatedInteractionResidentMemoryMiB",
            "repeatedInteractionThreadCount",
            "repeatedInteractionResidentMemoryGrowthBytes",
            "repeatedInteractionResidentMemoryGrowthMiB",
            "repeatedInteractionThreadGrowth",
            "repeatedInteractionRetainedThreadGrowth",
            "idleDurationMilliseconds",
            "idleProcessorTimeNanoseconds",
            "idleProcessorTimeMilliseconds",
            "idleCPUPercent",
            "idleResidentMemoryBytes",
            "idleResidentMemoryMiB",
            "idleResidentMemoryGrowthBytes",
            "idleResidentMemoryGrowthMiB",
            "idleThreadCount",
            "idleThreadGrowth"
        ]
        for field in summaryFields {
            evidence[field] = selectedAttempt[field]
        }
        return evidence
    }

    private func performanceAttempt(
        number: Int,
        launchReadyMilliseconds: Double,
        residentMiB: Int,
        postInteractionMiB: Int,
        repeatedInteractionMiB: Int,
        threadCount: Int,
        postInteractionThreadCount: Int,
        repeatedInteractionThreadCount: Int
    ) -> [String: Any] {
        let resident = residentMiB * 1_024 * 1_024
        let postResident = postInteractionMiB * 1_024 * 1_024
        let repeatedResident = repeatedInteractionMiB * 1_024 * 1_024
        let idleResident = repeatedResident + 1 * 1_024 * 1_024
        let residentGrowth = postResident - resident
        let repeatedResidentGrowth = repeatedResident - postResident
        return [
            "attempt": number,
            "launchReadyMilliseconds": launchReadyMilliseconds,
            "residentMemoryBytes": resident,
            "residentMemoryMiB": Double(residentMiB),
            "threadCount": threadCount,
            "postInteractionResidentMemoryBytes": postResident,
            "postInteractionResidentMemoryMiB": Double(postInteractionMiB),
            "postInteractionThreadCount": postInteractionThreadCount,
            "residentMemoryGrowthBytes": residentGrowth,
            "residentMemoryGrowthMiB": Double(residentGrowth) / Double(1_024 * 1_024),
            "threadGrowth": postInteractionThreadCount - threadCount,
            "repeatedInteractionResidentMemoryBytes": repeatedResident,
            "repeatedInteractionResidentMemoryMiB": Double(repeatedInteractionMiB),
            "repeatedInteractionThreadCount": repeatedInteractionThreadCount,
            "repeatedInteractionResidentMemoryGrowthBytes": repeatedResidentGrowth,
            "repeatedInteractionResidentMemoryGrowthMiB": (
                Double(repeatedResidentGrowth) / Double(1_024 * 1_024)
            ),
            "repeatedInteractionThreadGrowth": (
                repeatedInteractionThreadCount - postInteractionThreadCount
            ),
            "repeatedInteractionRetainedThreadGrowth": (
                repeatedInteractionThreadCount
                    - max(threadCount, postInteractionThreadCount)
            ),
            "idleDurationMilliseconds": 2_000.0,
            "idleProcessorTimeNanoseconds": 100_000_000,
            "idleProcessorTimeMilliseconds": 100.0,
            "idleCPUPercent": 5.0,
            "idleResidentMemoryBytes": idleResident,
            "idleResidentMemoryMiB": Double(repeatedInteractionMiB + 1),
            "idleResidentMemoryGrowthBytes": 1 * 1_024 * 1_024,
            "idleResidentMemoryGrowthMiB": 1.0,
            "idleThreadCount": repeatedInteractionThreadCount,
            "idleThreadGrowth": 0,
            "withinLaunchBudget": launchReadyMilliseconds <= 2_500,
            "withinResidentMemoryBudget": true,
            "withinResidentMemoryGrowthBudget": true,
            "withinRepeatedResidentMemoryGrowthBudget": true,
            "withinThreadCountBudget": true,
            "withinRepeatedRetainedThreadGrowthBudget": true,
            "withinIdleCPUPercentBudget": true,
            "withinIdleResidentMemoryGrowthBudget": true,
            "withinIdleThreadGrowthBudget": true
        ]
    }

    private func manifestAsset(
        named name: String,
        kind: String,
        platform: String,
        arch: String,
        install: String,
        assetsURL: URL,
        releaseTag: String
    ) throws -> [String: Any] {
        let url = assetsURL.appendingPathComponent(name)
        return [
            "name": name,
            "kind": kind,
            "platform": platform,
            "arch": arch,
            "install": install,
            "sizeBytes": try Data(contentsOf: url).count,
            "sha256": try sha256(at: url),
            "url": releaseDownloadURL(named: name, tag: releaseTag)
        ]
    }

    private func writeAppArchive(
        to archiveURL: URL,
        commit: String,
        architecture: String,
        root: URL,
        infoIsSymlink: Bool,
        channel: String,
        updateManifestURL: String,
        signingTeamIdentifier: String?
    ) throws {
        let scriptURL = root.appendingPathComponent("make-app-archive.py")
        try """
        import plistlib
        import struct
        import sys
        import zipfile

        values = {
            "CFBundleName": "Quill Cowork",
            "CFBundleDisplayName": "Quill Cowork",
            "CFBundleIdentifier": "co.lorehex.QuillCowork",
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "123",
            "LSMinimumSystemVersion": "14.0",
            "QuillCodeBuildCommit": sys.argv[2],
            "QuillCodeUpdateChannel": sys.argv[3],
            "QuillCodeUpdateManifestURL": sys.argv[4],
            "QuillCodeStableUpdateManifestURL": sys.argv[5],
            "QuillCodeTesterUpdateManifestURL": sys.argv[6],
        }
        if sys.argv[7] != "none":
            values["QuillCodeSigningTeamIdentifier"] = sys.argv[7]
        with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as archive:
            path = "Quill Cowork.app/Contents/Info.plist"
            if sys.argv[8] == "symlink":
                entry = zipfile.ZipInfo(path)
                entry.create_system = 3
                entry.external_attr = 0o120777 << 16
                archive.writestr(entry, b"Info.plist")
            else:
                archive.writestr(path, plistlib.dumps(values))
            cpu_types = {"arm64": 0x0100000C, "x86_64": 0x01000007}
            executable = struct.pack(
                "<IIIIIIII", 0xFEEDFACF, cpu_types[sys.argv[9]], 0, 2, 0, 0, 0, 0
            )
            archive.writestr("Quill Cowork.app/Contents/MacOS/Quill Cowork", executable)
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        let result = try Self.runPython(scriptURL, arguments: [
            archiveURL.path,
            commit,
            channel,
            updateManifestURL,
            stableManifestURL,
            testerManifestURL,
            signingTeamIdentifier ?? "none",
            infoIsSymlink ? "symlink" : "regular",
            architecture
        ])
        try FileManager.default.removeItem(at: scriptURL)
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "ParityPublishedReleaseVerificationGateTests",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
    }

    private func runVerifier(
        _ fixture: Fixture,
        tagCommit: String? = nil,
        stableCandidate: Bool = false,
        discoverWorkflowRunURL: Bool = false
    ) throws -> ScriptResult {
        let script = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("verify-published-release.py")
        var arguments = [
            "--repo", repository,
            "--tag", fixture.tag,
            "--channel", fixture.channel,
            "--commit", commit,
            "--release-json", fixture.releaseJSON.path,
            "--tag-commit", tagCommit ?? commit,
            "--manifest", fixture.manifest.path,
            "--assets-dir", fixture.assets.path
        ]
        if discoverWorkflowRunURL {
            arguments.append("--discover-workflow-run-url")
        } else {
            arguments.append(contentsOf: ["--workflow-run-url", workflowRunURL])
        }
        if stableCandidate {
            arguments.append("--stable-candidate")
        } else if fixture.channel == "stable" {
            arguments.append(contentsOf: [
                "--latest-release-json", try XCTUnwrap(fixture.latestReleaseJSON).path,
                "--stable-feed-manifest", try XCTUnwrap(fixture.stableFeedManifest).path
            ])
        }
        return try Self.runPython(script, arguments: arguments)
    }

    private func mutateManifest(
        _ fixture: Fixture,
        mutation: (inout [String: Any]) throws -> Void
    ) throws {
        var manifest = try jsonObject(at: fixture.manifest)
        try mutation(&manifest)
        try writeJSON(manifest, to: fixture.manifest)

        var release = try jsonObject(at: fixture.releaseJSON)
        var assets = try XCTUnwrap(release["assets"] as? [[String: Any]])
        let index = try XCTUnwrap(assets.firstIndex { $0["name"] as? String == fixture.manifest.lastPathComponent })
        assets[index]["size"] = try Data(contentsOf: fixture.manifest).count
        assets[index]["digest"] = "sha256:\(try sha256(at: fixture.manifest))"
        release["assets"] = assets
        try writeJSON(release, to: fixture.releaseJSON)
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeJSON(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: url)
    }

    private func sha256(at url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func releaseDownloadURL(named name: String, tag releaseTag: String? = nil) -> String {
        "https://github.com/\(repository)/releases/download/\(releaseTag ?? tag)/\(name)"
    }

    private var testerManifestURL: String {
        releaseDownloadURL(named: "latest-tester-build.json")
    }

    private var stableManifestURL: String {
        "https://github.com/\(repository)/releases/latest/download/latest-stable-build.json"
    }
}
