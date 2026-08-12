import Foundation
import XCTest

final class ParityUpdaterSourceCaptureTests: QuillCodeParityTestCase {
    private let commit = String(repeating: "a", count: 40)

    func testCaptureVerifiesAndPersistsThePreviousPublicApp() throws {
        let result = try runCapture()
        defer { try? FileManager.default.removeItem(at: result.root) }

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Captured tester arm64 updater source"), result.output)
        let capture = try jsonObject(at: result.outputDirectory.appendingPathComponent("capture.json"))
        XCTAssertEqual(capture["schemaVersion"] as? Int, 1)
        XCTAssertEqual(capture["sourceAvailable"] as? Bool, true)
        XCTAssertEqual(capture["channel"] as? String, "tester")
        XCTAssertEqual(capture["tag"] as? String, "tester-latest")
        XCTAssertEqual(capture["architecture"] as? String, "arm64")
        XCTAssertEqual(capture["version"] as? String, "0.1.0")
        XCTAssertEqual(capture["build"] as? String, "695")
        XCTAssertEqual(capture["commit"] as? String, commit)
        XCTAssertEqual(capture["appName"] as? String, "Quill-Cowork-macOS-arm64.zip")
        XCTAssertEqual(
            try Data(contentsOf: result.outputDirectory.appendingPathComponent("source-app.zip")),
            result.appData
        )
        XCTAssertEqual(
            try Data(contentsOf: result.outputDirectory.appendingPathComponent("source-manifest.json")),
            result.manifestData
        )
        XCTAssertEqual(
            result.operations,
            [
                "api:repos/Lore-Hex/QuillCode/releases/tags/tester-latest",
                "download:tester-latest:latest-tester-build.json",
                "download:tester-latest:Quill-Cowork-macOS-arm64.zip"
            ]
        )
    }

    func testMissingFirstReleaseWritesOnlyAnExplicitFallbackRecord() throws {
        let result = try runCapture(missing: true)
        defer { try? FileManager.default.removeItem(at: result.root) }

        XCTAssertEqual(result.exitCode, 0, result.output)
        let capture = try jsonObject(at: result.outputDirectory.appendingPathComponent("capture.json"))
        XCTAssertEqual(capture["sourceAvailable"] as? Bool, false)
        XCTAssertEqual(capture["reason"] as? String, "release-not-found")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.outputDirectory.appendingPathComponent("source-app.zip").path
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: result.outputDirectory.path),
            ["capture.json"]
        )
        XCTAssertEqual(
            result.operations,
            ["api:repos/Lore-Hex/QuillCode/releases/tags/tester-latest"]
        )
    }

    func testMissingStableChannelUsesTheLatestReleaseEndpoint() throws {
        let result = try runCapture(missing: true, channel: "stable")
        defer { try? FileManager.default.removeItem(at: result.root) }

        XCTAssertEqual(result.exitCode, 0, result.output)
        let capture = try jsonObject(at: result.outputDirectory.appendingPathComponent("capture.json"))
        XCTAssertEqual(capture["sourceAvailable"] as? Bool, false)
        XCTAssertEqual(capture["channel"] as? String, "stable")
        XCTAssertEqual(result.operations, ["api:repos/Lore-Hex/QuillCode/releases/latest"])
    }

    func testCorruptDownloadFailsTransactionallyWithoutPublishingCapture() throws {
        let result = try runCapture(corruptAsset: "Quill-Cowork-macOS-arm64.zip")
        defer { try? FileManager.default.removeItem(at: result.root) }

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("digest disagrees"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.outputDirectory.path))
        let abandonedStaging = try FileManager.default.contentsOfDirectory(atPath: result.root.path)
            .filter { $0.hasPrefix(".capture.capture-") }
        XCTAssertEqual(abandonedStaging, [])
    }

    func testUnsafeRepositoryFailsBeforeCallingGitHub() throws {
        let result = try runCapture(repository: "owner/..")
        defer { try? FileManager.default.removeItem(at: result.root) }

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Repository must use owner/name syntax"), result.output)
        XCTAssertEqual(result.operations, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.outputDirectory.path))
    }

    private struct CaptureResult {
        let exitCode: Int32
        let output: String
        let root: URL
        let outputDirectory: URL
        let appData: Data
        let manifestData: Data
        let operations: [String]
    }

    private func runCapture(
        missing: Bool = false,
        corruptAsset: String? = nil,
        repository: String = "Lore-Hex/QuillCode",
        channel: String = "tester"
    ) throws -> CaptureResult {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-updater-source-capture-tests")
            .appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("bin")
        let fixtures = root.appendingPathComponent("fixtures")
        let stateURL = root.appendingPathComponent("state.json")
        let outputDirectory = root.appendingPathComponent("capture")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)

        let appName = "Quill-Cowork-macOS-arm64.zip"
        let manifestName = "latest-tester-build.json"
        let appData = Data("previous public app archive".utf8)
        let appDigest = try sha256(appData, in: root)
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "product": "Quill Cowork",
            "channel": "tester",
            "tag": "tester-latest",
            "commit": commit,
            "version": "0.1.0",
            "build": "695",
            "updater": [
                "bundleIdentifier": "co.lorehex.QuillCowork",
                "channel": "tester",
                "macOSAppAssets": [[
                    "arch": "arm64",
                    "name": appName,
                    "platform": "macOS",
                    "kind": "app",
                    "install": "zip-app",
                    "url": "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/\(appName)",
                    "sizeBytes": appData.count,
                    "sha256": appDigest
                ]]
            ]
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        let manifestDigest = try sha256(manifestData, in: root)
        try appData.write(to: fixtures.appendingPathComponent(appName))
        try manifestData.write(to: fixtures.appendingPathComponent(manifestName))

        let state: [String: Any] = [
            "missing": missing,
            "corruptAsset": (corruptAsset as Any?) ?? NSNull(),
            "operations": [],
            "fixtures": fixtures.path,
            "release": [
                "tag_name": "tester-latest",
                "target_commitish": commit,
                "draft": false,
                "prerelease": true,
                "assets": [
                    remoteAsset(name: manifestName, data: manifestData, digest: manifestDigest),
                    remoteAsset(name: appName, data: appData, digest: appDigest)
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]).write(to: stateURL)
        try writeExecutable(fakeGitHub, to: bin.appendingPathComponent("gh"))

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            Self.packageRoot().appendingPathComponent("scripts/capture-public-updater-source.py").path,
            "--repo", repository,
            "--channel", channel,
            "--arch", "arm64",
            "--output-dir", outputDirectory.path,
            "--allow-missing"
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):\(environment["PATH"] ?? "")"
        environment["FAKE_CAPTURE_STATE"] = stateURL.path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let finalState = try jsonObject(at: stateURL)
        let operations = try XCTUnwrap(finalState["operations"] as? [String])
        return CaptureResult(
            exitCode: process.terminationStatus,
            output: output,
            root: root,
            outputDirectory: outputDirectory,
            appData: appData,
            manifestData: manifestData,
            operations: operations
        )
    }

    private func remoteAsset(name: String, data: Data, digest: String) -> [String: Any] {
        [
            "name": name,
            "size": data.count,
            "digest": "sha256:\(digest)",
            "state": "uploaded"
        ]
    }

    private func sha256(_ data: Data, in directory: URL) throws -> String {
        let input = directory.appendingPathComponent("digest-\(UUID().uuidString)")
        try data.write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-c",
            "import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())",
            input.path
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertEqual(output.count, 64)
        return output
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeExecutable(_ source: String, to url: URL) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private var fakeGitHub: String {
        #"""
        #!/usr/bin/env python3
        import json
        import os
        from pathlib import Path
        import shutil
        import sys

        state_path = Path(os.environ["FAKE_CAPTURE_STATE"])

        def load():
            return json.loads(state_path.read_text())

        def save(state):
            temporary = state_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, sort_keys=True))
            temporary.replace(state_path)

        args = sys.argv[1:]
        state = load()
        if args[:1] == ["api"]:
            endpoint = next(value for value in args if value.startswith("repos/"))
            state["operations"].append("api:" + endpoint)
            save(state)
            if state["missing"]:
                print("HTTP 404: Not Found", file=sys.stderr)
                raise SystemExit(1)
            print(json.dumps(state["release"], sort_keys=True))
            raise SystemExit(0)
        if args[:2] == ["release", "download"]:
            tag = args[2]
            name = args[args.index("--pattern") + 1]
            destination = Path(args[args.index("--dir") + 1]) / name
            state["operations"].append("download:" + tag + ":" + name)
            save(state)
            shutil.copyfile(Path(state["fixtures"]) / name, destination)
            if state.get("corruptAsset") == name:
                contents = bytearray(destination.read_bytes())
                contents[0] ^= 0xff
                destination.write_bytes(contents)
            raise SystemExit(0)
        print("unsupported fake gh invocation: " + " ".join(args), file=sys.stderr)
        raise SystemExit(64)
        """#
    }
}
