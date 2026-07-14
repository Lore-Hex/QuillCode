import XCTest

final class ParityDownloadBuildsGateTests: QuillCodeParityTestCase {
    func testDownloadManifestGeneratorWritesStableTesterMetadata() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-download-manifest-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try "product=QuillCode\nplatform=macOS\narch=arm64\nversion=0.2.0\nbuild=123\n"
            .write(to: temporaryDirectory.appendingPathComponent("BUILD_INFO.txt"), atomically: true, encoding: .utf8)
        try "product=QuillCode\nplatform=Linux\narch=x86_64\nversion=0.2.0\nbuild=123\n"
            .write(
                to: temporaryDirectory.appendingPathComponent("BUILD_INFO-linux-x86_64.txt"),
                atomically: true,
                encoding: .utf8
            )
        try Data("mac app".utf8).write(to: temporaryDirectory.appendingPathComponent("QuillCode-macOS-arm64.zip"))
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
        XCTAssertEqual(manifest["product"] as? String, "QuillCode")
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

        let assets = try XCTUnwrap(manifest["assets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 6)

        let appAsset = try asset(named: "QuillCode-macOS-arm64.zip", in: assets)
        XCTAssertEqual(appAsset["kind"] as? String, "app")
        XCTAssertEqual(appAsset["platform"] as? String, "macOS")
        XCTAssertEqual(appAsset["arch"] as? String, "arm64")
        XCTAssertEqual(appAsset["install"] as? String, "zip-app")
        XCTAssertEqual(appAsset["url"] as? String, "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/QuillCode-macOS-arm64.zip")
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
            "group: download-builds-${{ github.ref }}",
            "cancel-in-progress: false",
            "scripts/build-download-manifest.py",
            "--output \"$RUNNER_TEMP/release-assets/latest-tester-build.json\"",
            "RELEASE_CHANNEL=\"tester\"",
            "RELEASE_CHANNEL=\"stable\"",
            "\\`latest-tester-build.json\\`: machine-readable build metadata",
            "gh release upload \"$RELEASE_TAG\" \"$RUNNER_TEMP\"/release-assets/* --clobber"
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
            "Build manifest",
            "channel is `tester`",
            "channel is `stable`"
        ])
        Self.assertSource(readme, contains: "machine-readable build manifest")
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
