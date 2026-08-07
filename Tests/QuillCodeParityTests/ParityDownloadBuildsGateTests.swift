import XCTest

final class ParityDownloadBuildsGateTests: QuillCodeParityTestCase {
    func testDownloadManifestGeneratorWritesStableTesterMetadata() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-download-manifest-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try """
        product=Quill Cowork
        platform=macOS
        arch=arm64
        version=0.2.0
        build=123
        bundleIdentifier=co.lorehex.QuillCowork
        minimumSystemVersion=14.0
        updateChannel=tester
        updateManifestURL=https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json
        stableUpdateManifestURL=https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json
        testerUpdateManifestURL=https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json
        """
            .write(to: temporaryDirectory.appendingPathComponent("BUILD_INFO.txt"), atomically: true, encoding: .utf8)
        try "product=Quill Cowork\nplatform=Linux\narch=x86_64\nversion=0.2.0\nbuild=123\n"
            .write(
                to: temporaryDirectory.appendingPathComponent("BUILD_INFO-linux-x86_64.txt"),
                atomically: true,
                encoding: .utf8
            )
        try Data("mac app".utf8).write(to: temporaryDirectory.appendingPathComponent("Quill-Cowork-macOS-arm64.zip"))
        try Data("mac cli".utf8).write(to: temporaryDirectory.appendingPathComponent("quill-code-macOS-arm64.tar.gz"))
        try Data("linux cli".utf8).write(to: temporaryDirectory.appendingPathComponent("quill-code-linux-x86_64.tar.gz"))
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
            "--commit", "abc123",
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
        XCTAssertEqual(manifest["commit"] as? String, "abc123")
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

        let assets = try XCTUnwrap(manifest["assets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 6)

        let appAsset = try asset(named: "Quill-Cowork-macOS-arm64.zip", in: assets)
        XCTAssertEqual(appAsset["kind"] as? String, "app")
        XCTAssertEqual(appAsset["platform"] as? String, "macOS")
        XCTAssertEqual(appAsset["arch"] as? String, "arm64")
        XCTAssertEqual(appAsset["install"] as? String, "zip-app")
        XCTAssertEqual(appAsset["url"] as? String, "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip")
        XCTAssertEqual(appAsset["sizeBytes"] as? Int, 7)
        XCTAssertEqual((appAsset["sha256"] as? String)?.count, 64)

        let linuxAsset = try asset(named: "quill-code-linux-x86_64.tar.gz", in: assets)
        XCTAssertEqual(linuxAsset["kind"] as? String, "cli")
        XCTAssertEqual(linuxAsset["platform"] as? String, "Linux")
        XCTAssertEqual(linuxAsset["arch"] as? String, "x86_64")

        let macMetadata = try asset(named: "BUILD_INFO.txt", in: assets)
        XCTAssertEqual(macMetadata["kind"] as? String, "metadata")
        XCTAssertEqual(macMetadata["platform"] as? String, "macOS")
        XCTAssertEqual(macMetadata["arch"] as? String, "any")

        let linuxMetadata = try asset(named: "BUILD_INFO-linux-x86_64.txt", in: assets)
        XCTAssertEqual(linuxMetadata["kind"] as? String, "metadata")
        XCTAssertEqual(linuxMetadata["platform"] as? String, "Linux")
        XCTAssertEqual(linuxMetadata["arch"] as? String, "x86_64")

        let checksumAsset = try asset(named: "SHASUMS256.txt", in: assets)
        XCTAssertEqual(checksumAsset["kind"] as? String, "checksum")
    }

    func testDownloadBuildWorkflowPublishesManifestWithReleaseAssets() throws {
        let workflow = try Self.workflowText(named: "download-builds.yml")

        Self.assertSource(workflow, containsAll: [
            "actions: read",
            "release-policy:",
            "scripts/validate-download-build-ref.sh",
            "needs: release-policy",
            "group: download-builds-${{ github.ref }}",
            "cancel-in-progress: false",
            "QUILLCODE_UPDATE_CHANNEL=stable",
            "QUILLCODE_UPDATE_CHANNEL=tester",
            "scripts/build-download-manifest.py",
            "MANIFEST_NAME=\"latest-${RELEASE_CHANNEL}-build.json\"",
            "--output \"$RUNNER_TEMP/release-assets/$MANIFEST_NAME\"",
            "RELEASE_CHANNEL=\"tester\"",
            "RELEASE_CHANNEL=\"stable\"",
            "quillcode-macos-downloads/BUILD_INFO.txt",
            "\\`${MANIFEST_NAME}\\`: machine-readable build metadata",
            "updater feed metadata",
            "current-release-assets.txt",
            "gh release delete-asset \"$RELEASE_TAG\" \"$asset_name\" --yes",
            "gh release upload \"$RELEASE_TAG\" \"$RUNNER_TEMP\"/release-assets/* --clobber",
            "--verify-tag",
            "--draft",
            "gh release upload \"$RELEASE_TAG\" \"$RUNNER_TEMP\"/release-assets/*",
            "gh release edit \"$RELEASE_TAG\" --draft=false --latest",
            "Stable release $RELEASE_TAG already exists and is immutable."
        ])
        XCTAssertFalse(
            workflow.contains("cancel-in-progress: true"),
            "a scheduled build must not cancel another run while it is publishing release assets"
        )
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
            "an existing stable release is never edited or clobbered automatically",
            "channel is `tester`",
            "channel is `stable`"
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

        Self.assertSource(buildScript, containsAll: [
            "QUILLCODE_MACOS_UPDATE_CHANNEL",
            "QUILLCODE_MACOS_UPDATE_MANIFEST_URL",
            "QUILLCODE_MACOS_UPDATE_STABLE_MANIFEST_URL",
            "QUILLCODE_MACOS_UPDATE_TESTER_MANIFEST_URL",
            "<key>QuillCodeUpdateChannel</key>",
            "<key>QuillCodeUpdateManifestURL</key>",
            "<key>QuillCodeStableUpdateManifestURL</key>",
            "<key>QuillCodeTesterUpdateManifestURL</key>",
            "QuillCodeSigningTeamIdentifier"
        ])
        Self.assertSource(packageScript, containsAll: [
            "bundleIdentifier=$BUNDLE_ID",
            "minimumSystemVersion=$MINIMUM_SYSTEM_VERSION",
            "updateChannel=$UPDATE_CHANNEL",
            "updateManifestURL=$UPDATE_MANIFEST_URL",
            "stableUpdateManifestURL=$STABLE_MANIFEST_URL",
            "testerUpdateManifestURL=$TESTER_MANIFEST_URL",
            "signingTeamIdentifier=${SIGNING_TEAM_IDENTIFIER:-none}",
            "notarized=$NOTARIZED"
        ])
        Self.assertSource(smokeScript, containsAll: [
            "assert_plist_value QuillCodeUpdateChannel tester",
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

        Self.assertSource(workflow, contains: "MERGE_TRAIN_POST_MERGE_WORKFLOWS: ci.yml download-builds.yml")
        Self.assertSource(script, containsAll: [
            "MERGE_TRAIN_POST_MERGE_WORKFLOWS",
            "MERGE_TRAIN_POST_MERGE_WORKFLOW",
            "gh workflow run \"$post_merge_workflow\" --repo \"$repo\" --ref \"$base_branch\""
        ])
        Self.assertSource(docs, containsAll: [
            "`CI` and `Download Builds` workflows",
            "refreshes the `tester-latest` download release"
        ])
    }

    private func asset(named name: String, in assets: [[String: Any]]) throws -> [String: Any] {
        try XCTUnwrap(assets.first { $0["name"] as? String == name })
    }
}
