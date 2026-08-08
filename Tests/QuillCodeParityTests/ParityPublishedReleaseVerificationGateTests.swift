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

    private struct Fixture {
        var root: URL
        var assets: URL
        var manifest: URL
        var releaseJSON: URL
    }

    private func makeFixture(
        appCommit: String? = nil,
        appInfoIsSymlink: Bool = false
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-cowork-release-verifier-tests")
            .appendingPathComponent(UUID().uuidString)
        let assetsURL = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let appName = "Quill-Cowork-macOS-arm64.zip"
        let cliName = "quill-code-macOS-arm64.tar.gz"
        let buildInfoName = "BUILD_INFO.txt"
        let checksumsName = "SHASUMS256.txt"
        try writeAppArchive(
            to: assetsURL.appendingPathComponent(appName),
            commit: appCommit ?? commit,
            root: root,
            infoIsSymlink: appInfoIsSymlink
        )
        try Data("verified cli payload".utf8).write(to: assetsURL.appendingPathComponent(cliName))
        try """
        product=Quill Cowork
        platform=macOS
        arch=arm64
        version=0.2.0
        build=123
        commit=\(commit)
        createdAt=2026-08-07T00:00:00Z
        configuration=release
        bundleIdentifier=co.lorehex.QuillCowork
        minimumSystemVersion=14.0
        updateChannel=tester
        updateManifestURL=\(testerManifestURL)
        stableUpdateManifestURL=\(stableManifestURL)
        testerUpdateManifestURL=\(testerManifestURL)
        app=\(appName)
        cli=\(cliName)
        codesign=ad-hoc
        signingTeamIdentifier=none
        notarized=false
        """.write(
            to: assetsURL.appendingPathComponent(buildInfoName),
            atomically: true,
            encoding: .utf8
        )

        let checksummedNames = [buildInfoName, appName, cliName].sorted()
        let checksumText = try checksummedNames.map { name in
            let digest = try sha256(at: assetsURL.appendingPathComponent(name))
            return "\(digest)  \(name)"
        }.joined(separator: "\n") + "\n"
        try checksumText.write(
            to: assetsURL.appendingPathComponent(checksumsName),
            atomically: true,
            encoding: .utf8
        )

        let appAsset = try manifestAsset(
            named: appName,
            kind: "app",
            platform: "macOS",
            arch: "arm64",
            install: "zip-app",
            assetsURL: assetsURL
        )
        let manifestAssets = try [
            manifestAsset(
                named: buildInfoName,
                kind: "metadata",
                platform: "macOS",
                arch: "any",
                install: "text",
                assetsURL: assetsURL
            ),
            appAsset,
            manifestAsset(
                named: checksumsName,
                kind: "checksum",
                platform: "any",
                arch: "any",
                install: "text",
                assetsURL: assetsURL
            ),
            manifestAsset(
                named: cliName,
                kind: "cli",
                platform: "macOS",
                arch: "arm64",
                install: "tarball",
                assetsURL: assetsURL
            )
        ]
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "product": "Quill Cowork",
            "channel": "tester",
            "tag": tag,
            "releaseURL": "https://github.com/\(repository)/releases/tag/\(tag)",
            "commit": commit,
            "version": "0.2.0",
            "build": "123",
            "generatedAt": "2026-08-07T00:00:01Z",
            "workflowRunURL": workflowRunURL,
            "updater": [
                "schemaVersion": 1,
                "format": "github-release-manifest",
                "channel": "tester",
                "manifestURL": testerManifestURL,
                "stableManifestURL": stableManifestURL,
                "testerManifestURL": testerManifestURL,
                "bundleIdentifier": "co.lorehex.QuillCowork",
                "minimumSystemVersion": "14.0",
                "codesign": "ad-hoc",
                "signingTeamIdentifier": NSNull(),
                "notarized": false,
                "macOSAppAsset": appAsset
            ],
            "assets": manifestAssets
        ]
        let manifestURL = root.appendingPathComponent("latest-tester-build.json")
        try writeJSON(manifest, to: manifestURL)

        var releaseAssets = try manifestAssets.map { asset -> [String: Any] in
            let name = try XCTUnwrap(asset["name"] as? String)
            return [
                "name": name,
                "state": "uploaded",
                "size": try XCTUnwrap(asset["sizeBytes"] as? Int),
                "digest": "sha256:\(try XCTUnwrap(asset["sha256"] as? String))",
                "browser_download_url": releaseDownloadURL(named: name)
            ]
        }
        releaseAssets.append([
            "name": manifestURL.lastPathComponent,
            "state": "uploaded",
            "size": try Data(contentsOf: manifestURL).count,
            "digest": "sha256:\(try sha256(at: manifestURL))",
            "browser_download_url": releaseDownloadURL(named: manifestURL.lastPathComponent)
        ])
        let release: [String: Any] = [
            "tag_name": tag,
            "draft": false,
            "prerelease": true,
            "assets": releaseAssets
        ]
        let releaseJSONURL = root.appendingPathComponent("release.json")
        try writeJSON(release, to: releaseJSONURL)
        return Fixture(root: root, assets: assetsURL, manifest: manifestURL, releaseJSON: releaseJSONURL)
    }

    private func manifestAsset(
        named name: String,
        kind: String,
        platform: String,
        arch: String,
        install: String,
        assetsURL: URL
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
            "url": releaseDownloadURL(named: name)
        ]
    }

    private func writeAppArchive(
        to archiveURL: URL,
        commit: String,
        root: URL,
        infoIsSymlink: Bool
    ) throws {
        let scriptURL = root.appendingPathComponent("make-app-archive.py")
        try """
        import plistlib
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
            "QuillCodeUpdateChannel": "tester",
            "QuillCodeUpdateManifestURL": sys.argv[3],
            "QuillCodeStableUpdateManifestURL": sys.argv[4],
            "QuillCodeTesterUpdateManifestURL": sys.argv[3],
        }
        with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as archive:
            path = "Quill Cowork.app/Contents/Info.plist"
            if sys.argv[5] == "symlink":
                entry = zipfile.ZipInfo(path)
                entry.create_system = 3
                entry.external_attr = 0o120777 << 16
                archive.writestr(entry, b"Info.plist")
            else:
                archive.writestr(path, plistlib.dumps(values))
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        let result = try Self.runPython(scriptURL, arguments: [
            archiveURL.path,
            commit,
            testerManifestURL,
            stableManifestURL,
            infoIsSymlink ? "symlink" : "regular"
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
        tagCommit: String? = nil
    ) throws -> ScriptResult {
        let script = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("verify-published-release.py")
        return try Self.runPython(script, arguments: [
            "--repo", repository,
            "--tag", tag,
            "--channel", "tester",
            "--commit", commit,
            "--workflow-run-url", workflowRunURL,
            "--release-json", fixture.releaseJSON.path,
            "--tag-commit", tagCommit ?? commit,
            "--manifest", fixture.manifest.path,
            "--assets-dir", fixture.assets.path
        ])
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

    private func releaseDownloadURL(named name: String) -> String {
        "https://github.com/\(repository)/releases/download/\(tag)/\(name)"
    }

    private var testerManifestURL: String {
        releaseDownloadURL(named: "latest-tester-build.json")
    }

    private var stableManifestURL: String {
        "https://github.com/\(repository)/releases/latest/download/latest-stable-build.json"
    }
}
