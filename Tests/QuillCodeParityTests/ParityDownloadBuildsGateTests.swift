import XCTest

final class ParityDownloadBuildsGateTests: QuillCodeParityTestCase {
    func testDownloadManifestGeneratorWritesStableTesterMetadata() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-download-manifest-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let commit = String(repeating: "a", count: 40)
        for architecture in ["arm64", "x86_64"] {
            let buildInfo = """
            product=Quill Cowork
            platform=macOS
            arch=\(architecture)
            version=0.2.0
            build=123
            commit=\(commit)
            configuration=release
            symbolsStripped=true
            executableSizeBytes=28311552
            bundleIdentifier=co.lorehex.QuillCowork
            minimumSystemVersion=14.0
            updateChannel=tester
            updateManifestURL=https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json
            stableUpdateManifestURL=https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json
            testerUpdateManifestURL=https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json
            """
            try buildInfo.write(
                to: temporaryDirectory.appendingPathComponent("BUILD_INFO-macOS-\(architecture).txt"),
                atomically: true,
                encoding: .utf8
            )
            if architecture == "arm64" {
                try buildInfo.write(
                    to: temporaryDirectory.appendingPathComponent("BUILD_INFO.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            let appPayload = architecture == "arm64" ? "mac app" : "intel app"
            try Data(appPayload.utf8).write(
                to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-\(architecture).zip")
            )
            try Data("mac installer \(architecture)".utf8).write(
                to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-\(architecture).dmg")
            )
            try Data(#"{"withinBudget":true}"#.utf8).write(
                to: temporaryDirectory.appendingPathComponent(
                    "Quill-Cowork-macOS-\(architecture)-PERFORMANCE.json"
                )
            )
            try Data("mac cli \(architecture)".utf8).write(
                to: temporaryDirectory.appendingPathComponent("quill-code-macOS-\(architecture).tar.gz")
            )
        }
        try Data("universal mac installer".utf8).write(
            to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-universal.dmg")
        )
        try "product=Quill Cowork\nplatform=Linux\narch=x86_64\nversion=0.2.0\nbuild=123\n"
            .write(
                to: temporaryDirectory.appendingPathComponent("BUILD_INFO-linux-x86_64.txt"),
                atomically: true,
                encoding: .utf8
            )
        try Data("linux cli".utf8).write(
            to: temporaryDirectory.appendingPathComponent("quill-code-linux-x86_64.tar.gz")
        )
        try "placeholder checksums\n"
            .write(to: temporaryDirectory.appendingPathComponent("SHASUMS256.txt"), atomically: true, encoding: .utf8)

        let manifestURL = temporaryDirectory.appendingPathComponent("latest-tester-build.json")
        let script = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-download-manifest.py")
        let result = try Self.runPython(script, arguments: [
            "--assets-dir", temporaryDirectory.path,
            "--repo", "Lore-Hex/QuillCode",
            "--tag", "tester-latest",
            "--channel", "tester",
            "--commit", commit,
            "--workflow-run-url", "https://github.com/Lore-Hex/QuillCode/actions/runs/1",
            "--generated-at", "2026-07-05T00:00:00Z",
            "--output", manifestURL.path
        ])
        XCTAssertEqual(result.exitCode, 0, result.output)

        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(manifest["schemaVersion"] as? Int, 1)
        XCTAssertEqual(manifest["product"] as? String, "Quill Cowork")
        XCTAssertEqual(manifest["channel"] as? String, "tester")
        XCTAssertEqual(manifest["tag"] as? String, "tester-latest")
        XCTAssertEqual(manifest["releaseURL"] as? String, "https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest")
        XCTAssertEqual(manifest["commit"] as? String, commit)
        XCTAssertEqual(manifest["version"] as? String, "0.2.0")
        XCTAssertEqual(manifest["build"] as? String, "123")
        XCTAssertEqual(manifest["generatedAt"] as? String, "2026-07-05T00:00:00Z")
        XCTAssertEqual(
            manifest["workflowRunURL"] as? String,
            "https://github.com/Lore-Hex/QuillCode/actions/runs/1"
        )

        let updater = try XCTUnwrap(manifest["updater"] as? [String: Any])
        XCTAssertEqual(updater["schemaVersion"] as? Int, 1)
        XCTAssertEqual(updater["format"] as? String, "github-release-manifest")
        XCTAssertEqual(updater["channel"] as? String, "tester")
        XCTAssertEqual(
            updater["manifestURL"] as? String,
            "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
        )
        XCTAssertEqual(
            updater["stableManifestURL"] as? String,
            "https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json"
        )
        XCTAssertEqual(
            updater["testerManifestURL"] as? String,
            "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
        )
        XCTAssertEqual(updater["bundleIdentifier"] as? String, "co.lorehex.QuillCowork")
        XCTAssertEqual(updater["minimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(updater["codesign"] as? String, "unknown")
        XCTAssertEqual(updater["notarized"] as? Bool, false)
        XCTAssertNil(updater["signingTeamIdentifier"] as? String)
        let updaterAppAsset = try XCTUnwrap(updater["macOSAppAsset"] as? [String: Any])
        XCTAssertEqual(updaterAppAsset["name"] as? String, "Quill-Cowork-macOS-arm64.zip")
        let updaterAppAssets = try XCTUnwrap(updater["macOSAppAssets"] as? [[String: Any]])
        XCTAssertEqual(
            updaterAppAssets.compactMap { $0["arch"] as? String },
            ["arm64", "x86_64"]
        )
        XCTAssertEqual(
            updaterAppAssets.compactMap { $0["name"] as? String },
            ["Quill-Cowork-macOS-arm64.zip", "Quill-Cowork-macOS-x86_64.zip"]
        )
        let universalInstaller = try XCTUnwrap(
            updater["macOSUniversalInstaller"] as? [String: Any]
        )
        XCTAssertEqual(universalInstaller["name"] as? String, "Quill-Cowork-macOS-universal.dmg")
        XCTAssertEqual(universalInstaller["arch"] as? String, "universal")

        let assets = try XCTUnwrap(manifest["assets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 15)

        let universalAsset = try asset(named: "Quill-Cowork-macOS-universal.dmg", in: assets)
        XCTAssertEqual(universalAsset["kind"] as? String, "installer")
        XCTAssertEqual(universalAsset["platform"] as? String, "macOS")
        XCTAssertEqual(universalAsset["arch"] as? String, "universal")
        XCTAssertEqual(universalAsset["install"] as? String, "dmg-app")

        let installerAsset = try asset(named: "Quill-Cowork-macOS-arm64.dmg", in: assets)
        XCTAssertEqual(installerAsset["kind"] as? String, "installer")
        XCTAssertEqual(installerAsset["platform"] as? String, "macOS")
        XCTAssertEqual(installerAsset["arch"] as? String, "arm64")
        XCTAssertEqual(installerAsset["install"] as? String, "dmg-app")

        let appAsset = try asset(named: "Quill-Cowork-macOS-arm64.zip", in: assets)
        XCTAssertEqual(appAsset["kind"] as? String, "app")
        XCTAssertEqual(appAsset["platform"] as? String, "macOS")
        XCTAssertEqual(appAsset["arch"] as? String, "arm64")
        XCTAssertEqual(appAsset["install"] as? String, "zip-app")
        XCTAssertEqual(appAsset["url"] as? String, "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip")
        XCTAssertEqual(appAsset["sizeBytes"] as? Int, 7)
        XCTAssertEqual((appAsset["sha256"] as? String)?.count, 64)

        let performanceAsset = try asset(
            named: "Quill-Cowork-macOS-arm64-PERFORMANCE.json",
            in: assets
        )
        XCTAssertEqual(performanceAsset["kind"] as? String, "performance")
        XCTAssertEqual(performanceAsset["platform"] as? String, "macOS")
        XCTAssertEqual(performanceAsset["arch"] as? String, "arm64")
        XCTAssertEqual(performanceAsset["install"] as? String, "json")

        let linuxAsset = try asset(named: "quill-code-linux-x86_64.tar.gz", in: assets)
        XCTAssertEqual(linuxAsset["kind"] as? String, "cli")
        XCTAssertEqual(linuxAsset["platform"] as? String, "Linux")
        XCTAssertEqual(linuxAsset["arch"] as? String, "x86_64")

        let macMetadata = try asset(named: "BUILD_INFO.txt", in: assets)
        XCTAssertEqual(macMetadata["kind"] as? String, "metadata")
        XCTAssertEqual(macMetadata["platform"] as? String, "macOS")
        XCTAssertEqual(macMetadata["arch"] as? String, "any")

        let intelMetadata = try asset(named: "BUILD_INFO-macOS-x86_64.txt", in: assets)
        XCTAssertEqual(intelMetadata["kind"] as? String, "metadata")
        XCTAssertEqual(intelMetadata["platform"] as? String, "macOS")
        XCTAssertEqual(intelMetadata["arch"] as? String, "x86_64")

        let linuxMetadata = try asset(named: "BUILD_INFO-linux-x86_64.txt", in: assets)
        XCTAssertEqual(linuxMetadata["kind"] as? String, "metadata")
        XCTAssertEqual(linuxMetadata["platform"] as? String, "Linux")
        XCTAssertEqual(linuxMetadata["arch"] as? String, "x86_64")

        let checksumAsset = try asset(named: "SHASUMS256.txt", in: assets)
        XCTAssertEqual(checksumAsset["kind"] as? String, "checksum")
    }

    func testStableManifestUsesTheMovingFeedEmbeddedInTheStableApp() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-stable-manifest-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let stableFeed = "https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json"
        let testerFeed = "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/" +
            "latest-tester-build.json"
        let commit = String(repeating: "a", count: 40)
        var buildInfoURLs: [URL] = []
        for architecture in ["arm64", "x86_64"] {
            let buildInfo = """
            product=Quill Cowork
            platform=macOS
            arch=\(architecture)
            version=1.2.3
            build=456
            commit=\(commit)
            configuration=release
            symbolsStripped=true
            executableSizeBytes=28311552
            bundleIdentifier=co.lorehex.QuillCowork
            minimumSystemVersion=14.0
            updateChannel=stable
            updateManifestURL=\(stableFeed)
            stableUpdateManifestURL=\(stableFeed)
            testerUpdateManifestURL=\(testerFeed)
            """
            let buildInfoURL = temporaryDirectory.appendingPathComponent(
                "BUILD_INFO-macOS-\(architecture).txt"
            )
            try buildInfo.write(to: buildInfoURL, atomically: true, encoding: .utf8)
            buildInfoURLs.append(buildInfoURL)
            if architecture == "arm64" {
                let canonicalURL = temporaryDirectory.appendingPathComponent("BUILD_INFO.txt")
                try buildInfo.write(to: canonicalURL, atomically: true, encoding: .utf8)
                buildInfoURLs.append(canonicalURL)
            }
            try Data("stable app \(architecture)".utf8).write(
                to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-\(architecture).zip")
            )
            try Data("stable installer \(architecture)".utf8).write(
                to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-\(architecture).dmg")
            )
            try Data("performance \(architecture)".utf8).write(
                to: temporaryDirectory.appendingPathComponent(
                    "Quill-Cowork-macOS-\(architecture)-PERFORMANCE.json"
                )
            )
            try Data("cli \(architecture)".utf8).write(
                to: temporaryDirectory.appendingPathComponent("quill-code-macOS-\(architecture).tar.gz")
            )
        }
        try Data("stable universal installer".utf8).write(
            to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-universal.dmg")
        )

        let manifestURL = temporaryDirectory.appendingPathComponent("latest-stable-build.json")
        let script = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-download-manifest.py")
        let arguments = [
            "--assets-dir", temporaryDirectory.path,
            "--repo", "Lore-Hex/QuillCode",
            "--tag", "v1.2.3",
            "--channel", "stable",
            "--commit", commit,
            "--workflow-run-url", "https://github.com/Lore-Hex/QuillCode/actions/runs/456",
            "--generated-at", "2026-08-07T00:00:00Z",
            "--output", manifestURL.path
        ]
        let result = try Self.runPython(script, arguments: arguments)
        XCTAssertEqual(result.exitCode, 0, result.output)

        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let updater = try XCTUnwrap(manifest["updater"] as? [String: Any])
        XCTAssertEqual(updater["channel"] as? String, "stable")
        XCTAssertEqual(updater["manifestURL"] as? String, stableFeed)
        XCTAssertEqual(updater["stableManifestURL"] as? String, stableFeed)
        XCTAssertEqual(updater["testerManifestURL"] as? String, testerFeed)

        for buildInfoURL in buildInfoURLs {
            let mismatchedBuildInfo = try String(contentsOf: buildInfoURL, encoding: .utf8)
                .replacingOccurrences(
                    of: stableFeed,
                    with: "https://example.com/stable.json",
                    options: [],
                    range: nil
                )
            try mismatchedBuildInfo.write(to: buildInfoURL, atomically: true, encoding: .utf8)
        }
        let mismatch = try Self.runPython(script, arguments: arguments)
        XCTAssertNotEqual(mismatch.exitCode, 0)
        XCTAssertTrue(mismatch.output.contains("BUILD_INFO updateManifestURL must be"), mismatch.output)
    }

    func testDownloadBuildWorkflowPublishesManifestWithReleaseAssets() throws {
        let workflow = try Self.workflowText(named: "download-builds.yml")

        Self.assertSource(workflow, containsAll: [
            "permissions: {}",
            "actions: read",
            "contents: read",
            "contents: write",
            "release-policy:",
            "description: Build a fresh tester release or only verify the current public release",
            "- verify-current",
            "DOWNLOAD_BUILD_MODE: ${{ inputs.mode || 'build' }}",
            "scripts/validate-download-build-ref.sh",
            "Validate stable Apple distribution credentials",
            "scripts/validate-apple-distribution-credentials.sh",
            "Wait for successful exact-main CI",
            "scripts/wait-for-successful-ci.sh",
            "timeout-minutes: 65",
            "DOWNLOAD_BUILD_CI_WAIT_SECONDS: \"1800\"",
            "DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS: \"1800\"",
            "scripts/plan-download-build.sh",
            "build-required: ${{ steps.plan.outputs.build-required }}",
            "if: needs.release-policy.outputs.build-required == 'true'",
            "verify-current-published:",
            "if: needs.release-policy.outputs.build-required == 'false'",
            "Reverify current public tester release",
            "--discover-workflow-run-url",
            "verify-current-daily-driver:",
            "needs: [release-policy, verify-current-published]",
            "scripts/public-macos-daily-driver-smoke.sh",
            "name: quillcode-public-daily-driver-${{ matrix.arch }}",
            "retention-days: 30",
            "persist-credentials: false",
            "needs: release-policy",
            "capture-updater-source:",
            "scripts/capture-public-updater-source.py",
            "--output-dir \"$RUNNER_TEMP/prior-updater/$architecture\"",
            "--allow-missing",
            "name: quillcode-prior-updater-sources",
            "group: download-builds-${{ github.ref }}",
            "cancel-in-progress: false",
            "QUILLCODE_UPDATE_CHANNEL=stable",
            "QUILLCODE_UPDATE_CHANNEL=tester",
            "scripts/build-download-manifest.py",
            "MANIFEST_NAME=\"latest-${RELEASE_CHANNEL}-build.json\"",
            "--output \"$RUNNER_TEMP/release-assets/$MANIFEST_NAME\"",
            "RELEASE_CHANNEL=\"tester\"",
            "RELEASE_CHANNEL=\"stable\"",
            "quillcode-macos-downloads-arm64/BUILD_INFO-macOS-arm64.txt",
            "macos-15-intel",
            "runner: macos-15",
            "runner: macos-15-intel",
            "name: quillcode-macos-downloads-${{ matrix.arch }}",
            "macos-universal:",
            "scripts/package-macos-universal-installer.sh",
            "--arm64-app-zip",
            "--x86-64-app-zip",
            "Quill-Cowork-macOS-universal.dmg",
            "name: quillcode-macos-downloads-universal",
            "name: quillcode-public-updater-smoke-${{ matrix.arch }}",
            "scripts/build-release-notes.py",
            "--build-info \"$RUNNER_TEMP/release-assets/BUILD_INFO.txt\"",
            "--tag \"$RELEASE_TAG\"",
            "--channel \"$RELEASE_CHANNEL\"",
            "--commit \"$GITHUB_SHA\"",
            "--output \"$RUNNER_TEMP/release-notes.md\"",
            "scripts/plan-download-publication.sh",
            "needs: [macos, macos-universal, linux, capture-updater-source]",
            "pattern: quillcode-*-downloads*",
            "published: ${{ steps.publication.outputs.publish-required }}",
            "if: steps.publication.outputs.publish-required == 'true'",
            "if: needs.publish.outputs.published == 'true'",
            "scripts/publish-tester-release.py",
            "--assets-dir \"$RUNNER_TEMP/release-assets\"",
            "--notes-file \"$RUNNER_TEMP/release-notes.md\"",
            "--repo \"$GITHUB_REPOSITORY\"",
            "--run-id \"$GITHUB_RUN_ID\"",
            "--verify-tag",
            "--draft",
            "gh release upload \"$RELEASE_TAG\" \"$RUNNER_TEMP\"/release-assets/*",
            "--prerelease",
            "--latest=false",
            "Stable release $RELEASE_TAG already exists and is immutable.",
            "verify-published:",
            "needs: publish",
            "Verify public release downloads",
            "scripts/verify-published-release.py",
            "--workflow-run-url \"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID\"",
            "VERIFY_ARGUMENTS+=(--stable-candidate)",
            "quarantine-stable-candidate:",
            "Return failed stable candidate to draft",
            "needs.verify-published.result != 'success'",
            "needs.verify-updater.result != 'success'",
            "promote-stable:",
            "Promote verified stable candidate",
            "--prerelease=false",
            "needs: [publish, verify-published, capture-updater-source]",
            "needs: [publish, verify-published, verify-updater]",
            "needs.capture-updater-source.result == 'success'",
            "Download previous public updater source",
            "sourceAvailable raw",
            "Verify universal installer launches natively",
            "--expected-architecture '${{ matrix.arch }}'",
            "--source-manifest \"$CAPTURE_DIR/source-manifest.json\"",
            "verify-stable-promotion:",
            "needs: [promote-stable, verify-updater]",
            "Verify promoted stable release",
            "quarantine-promoted-stable:",
            "Return failed promoted stable release to draft",
            "needs.verify-stable-promotion.result != 'success'",
            "--draft --latest=false"
        ])
        XCTAssertFalse(
            workflow.contains("cancel-in-progress: true"),
            "a scheduled build must not cancel another run while it is publishing release assets"
        )
        XCTAssertFalse(
            workflow.contains("permissions:\n  actions: read\n  contents: write"),
            "repository write permission must remain scoped to the publish job"
        )
        XCTAssertFalse(workflow.contains("cat > \"$RUNNER_TEMP/release-notes.md\""))
        XCTAssertFalse(workflow.contains("MACOS_DISTRIBUTION_NOTE"))
        XCTAssertFalse(workflow.contains("--clobber"))
        XCTAssertFalse(workflow.contains("gh release delete-asset"))
        let validationIndex = try XCTUnwrap(workflow.range(of: "scripts/validate-download-build-ref.sh"))
        let applePreflightIndex = try XCTUnwrap(
            workflow.range(of: "scripts/validate-apple-distribution-credentials.sh")
        )
        let ciGateIndex = try XCTUnwrap(workflow.range(of: "scripts/wait-for-successful-ci.sh"))
        let planningIndex = try XCTUnwrap(workflow.range(of: "scripts/plan-download-build.sh"))
        XCTAssertLessThan(validationIndex.lowerBound, applePreflightIndex.lowerBound)
        XCTAssertLessThan(applePreflightIndex.lowerBound, ciGateIndex.lowerBound)
        XCTAssertLessThan(ciGateIndex.lowerBound, planningIndex.lowerBound)
        let publishIndex = try XCTUnwrap(workflow.range(of: "  publish:"))
        let sourceCaptureIndex = try XCTUnwrap(workflow.range(of: "  capture-updater-source:"))
        let freshnessIndex = try XCTUnwrap(workflow.range(of: "scripts/plan-download-publication.sh"))
        let releaseMutationIndex = try XCTUnwrap(workflow.range(of: "scripts/publish-tester-release.py"))
        let publicVerificationIndex = try XCTUnwrap(workflow.range(of: "  verify-published:"))
        let promotionIndex = try XCTUnwrap(workflow.range(of: "  promote-stable:"))
        let updaterIndex = try XCTUnwrap(workflow.range(of: "  verify-updater:"))
        let finalVerificationIndex = try XCTUnwrap(workflow.range(of: "  verify-stable-promotion:"))
        XCTAssertLessThan(sourceCaptureIndex.lowerBound, publishIndex.lowerBound)
        XCTAssertLessThan(publishIndex.lowerBound, publicVerificationIndex.lowerBound)
        XCTAssertLessThan(freshnessIndex.lowerBound, releaseMutationIndex.lowerBound)
        XCTAssertLessThan(publicVerificationIndex.lowerBound, updaterIndex.lowerBound)
        XCTAssertLessThan(updaterIndex.lowerBound, promotionIndex.lowerBound)
        XCTAssertLessThan(updaterIndex.lowerBound, finalVerificationIndex.lowerBound)
        XCTAssertLessThan(promotionIndex.lowerBound, finalVerificationIndex.lowerBound)
    }

    func testDownloadDocsExposeStableManifestLink() throws {
        let downloads = try Self.docsText(named: "DOWNLOADS.md")
        let readme = try String(contentsOf: Self.packageRoot().appendingPathComponent("README.md"), encoding: .utf8)

        Self.assertSource(downloads, containsAll: [
            "latest-tester-build.json",
            "latest-stable-build.json",
            "app updater, website, and support script contract",
            "Auto-Update Contract",
            "QuillCodeUpdateChannel",
            "QuillCodeUpdateManifestURL",
            "QuillCodeStableUpdateManifestURL",
            "QuillCodeTesterUpdateManifestURL",
            "canonical `vMAJOR.MINOR.PATCH` tag",
            "scripts/start-stable-release.sh --check-only v0.1.0",
            "scripts/verify-published-release.py",
            "same moving channel feed embedded",
            "publication is not green until this consumer check passes",
            "creates one annotated tag and pushes it without force",
            "Pre-existing stable releases remain untouched",
            "non-latest prerelease candidate",
            "returns the new release to draft",
            "previous stable feed",
            "avoids no-op build-number updates and unnecessary",
            "does not skip product verification",
            "mode=verify-current",
            "does not allocate a build number or mutate release assets",
            "three-process 100-chat daily-driver workload",
            "Raw reports and screenshots are retained for 30 days",
            "untouched previous public app",
            "synthetic one-build-behind fallback",
            "channel is `tester`",
            "channel is `stable`",
            "Quill-Cowork-macOS-universal.dmg"
        ])
        Self.assertSource(readme, contains: "machine-readable build manifest")
    }

    func testMacOSDownloadPackagingEmbedsUpdaterMetadata() throws {
        let root = Self.packageRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts").appendingPathComponent("build-macos-app.sh"),
            encoding: .utf8
        )
        let packageScript = try String(
            contentsOf: root.appendingPathComponent("scripts").appendingPathComponent("package-macos-downloads.sh"),
            encoding: .utf8
        )
        let smokeScript = try String(
            contentsOf: root.appendingPathComponent("scripts").appendingPathComponent("packaged-macos-smoke.sh"),
            encoding: .utf8
        )
        let diskImageScript = try String(
            contentsOf: root.appendingPathComponent("scripts").appendingPathComponent("create-macos-disk-image.sh"),
            encoding: .utf8
        )
        let universalInstallerScript = try String(
            contentsOf: root.appendingPathComponent("scripts")
                .appendingPathComponent("package-macos-universal-installer.sh"),
            encoding: .utf8
        )

        Self.assertSource(buildScript, containsAll: [
            "QUILLCODE_MACOS_UPDATE_CHANNEL",
            "QUILLCODE_MACOS_UPDATE_MANIFEST_URL",
            "QUILLCODE_MACOS_UPDATE_STABLE_MANIFEST_URL",
            "QUILLCODE_MACOS_UPDATE_TESTER_MANIFEST_URL",
            "<key>QuillCodeUpdateChannel</key>",
            "<key>QuillCodeUpdateManifestURL</key>",
            "<key>QuillCodeStableUpdateManifestURL</key>",
            "<key>QuillCodeTesterUpdateManifestURL</key>",
            "<key>QuillCodeBuildCommit</key>",
            "QuillCodeSigningTeamIdentifier",
            #"${QUILLCODE_MACOS_ADHOC_CODESIGN:-1}"#
        ])
        Self.assertSource(buildScript, contains: """
          <key>NSSupportsSuddenTermination</key>
          <false/>
        """)
        Self.assertSource(packageScript, containsAll: [
            "bundleIdentifier=$BUNDLE_ID",
            "minimumSystemVersion=$MINIMUM_SYSTEM_VERSION",
            "updateChannel=$UPDATE_CHANNEL",
            "updateManifestURL=$UPDATE_MANIFEST_URL",
            "stableUpdateManifestURL=$STABLE_MANIFEST_URL",
            "testerUpdateManifestURL=$TESTER_MANIFEST_URL",
            "QUILLCODE_MACOS_BUILD_COMMIT=\"$COMMIT\"",
            "installer=Quill-Cowork-macOS-$ARCH.dmg",
            "performance=Quill-Cowork-macOS-$ARCH-PERFORMANCE.json",
            "SYMBOLS_STRIPPED=false",
            #"if [[ "$CONFIGURATION" == "release" ]]; then"#,
            "SYMBOLS_STRIPPED=true",
            "symbolsStripped=$SYMBOLS_STRIPPED",
            "executableSizeBytes=$APP_EXECUTABLE_SIZE_BYTES",
            "stat -f '%z' \"$APP_EXECUTABLE\"",
            "scripts/packaged-macos-performance-smoke.sh",
            "scripts/create-macos-disk-image.sh",
            "signingTeamIdentifier=${SIGNING_TEAM_IDENTIFIER:-none}",
            "notarized=$NOTARIZED",
            "BUILD_INFO-macOS-$ARCH.txt"
        ])
        Self.assertSource(diskImageScript, containsAll: [
            "\"$DITTO_BIN\" \"$APP_BUNDLE\" \"$STAGING_DIR/$APP_NAME\"",
            "ln -s /Applications \"$STAGING_DIR/Applications\"",
            "\"$HDIUTIL_BIN\" create",
            "\"$HDIUTIL_BIN\" verify",
            "\"$HDIUTIL_BIN\" attach",
            "run_image_operation",
            "Retrying disk-image packaging after transient $FAILED_STAGE failure.",
            "refusing to retry",
            "mv -f \"$CANDIDATE_PATH\" \"$OUTPUT_PATH\"",
            "\"$CODESIGN_BIN\" --verify --deep --strict"
        ])
        Self.assertSource(diskImageScript, excludes: "-quiet")
        Self.assertSource(universalInstallerScript, containsAll: [
            "--arm64-app-zip",
            "--x86-64-app-zip",
            "lipo",
            "-verify_arch arm64 x86_64",
            "The arm64 and x86_64 app bundle inventories do not match.",
            "codesign",
            "notarytool submit",
            "scripts/create-macos-disk-image.sh",
            "scripts/packaged-macos-relocation-smoke.sh"
        ])
        Self.assertSource(smokeScript, containsAll: [
            "assert_plist_value QuillCodeUpdateChannel tester",
            "assert_plist_value QuillCodeBuildCommit \"$EXPECTED_BUILD_COMMIT\"",
            "assert_plist_value NSSupportsSuddenTermination false",
            "assert_plist_value QuillCodeUpdateManifestURL https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json",
            "assert_plist_value QuillCodeStableUpdateManifestURL https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json",
            "assert_plist_value QuillCodeTesterUpdateManifestURL https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json"
        ])
    }

    func testMergeTrainRefreshesTesterDownloadsAfterMerges() throws {
        let workflow = try Self.workflowText(named: "merge-train.yml")
        let script = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("scripts/merge-train.sh"),
            encoding: .utf8
        )
        let docs = try Self.docsText(named: "MERGE_TRAIN.md")

        Self.assertSource(
            workflow,
            contains: "MERGE_TRAIN_POST_MERGE_WORKFLOWS: ci.yml download-builds.yml website.yml"
        )
        Self.assertSource(script, containsAll: [
            "MERGE_TRAIN_POST_MERGE_WORKFLOWS",
            "MERGE_TRAIN_POST_MERGE_WORKFLOW",
            "gh workflow run \"$post_merge_workflow\" --repo \"$repo\" --ref \"$base_branch\""
        ])
        Self.assertSource(docs, containsAll: [
            "`CI`, `Download Builds`, and `Website` workflows",
            "refreshes the `tester-latest` download release"
        ])
    }

    private func asset(named name: String, in assets: [[String: Any]]) throws -> [String: Any] {
        try XCTUnwrap(assets.first { $0["name"] as? String == name })
    }
}
