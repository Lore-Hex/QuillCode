import XCTest

final class ParityTransactionalTesterPublicationTests: QuillCodeParityTestCase {
    private let oldCommit = String(repeating: "b", count: 40)
    private let newCommit = String(repeating: "a", count: 40)

    func testSuccessfulPublicationStagesVerifiesSwapsAndMovesTagLast() throws {
        let result = try runPublisher()

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Published transactional tester release"), result.output)
        XCTAssertEqual(result.state["tag"] as? String, newCommit)
        let release = try release(from: result.state)
        XCTAssertEqual(release["target_commitish"] as? String, newCommit)
        XCTAssertEqual(release["name"] as? String, "Quill Cowork Tester Build")
        XCTAssertEqual(release["body"] as? String, "New release notes\n")
        XCTAssertEqual(release["draft"] as? Bool, false)
        XCTAssertEqual(release["prerelease"] as? Bool, true)
        XCTAssertEqual(
            try assetNames(in: release),
            ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "new-evidence.json"]
        )

        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        let uploadIndexes = operations.indices.filter { operations[$0].hasPrefix("upload:") }
        let firstRename = try XCTUnwrap(
            operations.firstIndex { $0.hasPrefix("rename:") }
        )
        let releasePatch = try XCTUnwrap(operations.firstIndex(of: "patch-release"))
        let tagPush = try XCTUnwrap(operations.firstIndex(of: "push-tag:\(newCommit)"))
        let firstDelete = try XCTUnwrap(
            operations.firstIndex { $0.hasPrefix("delete:") }
        )
        XCTAssertEqual(uploadIndexes.count, 3)
        XCTAssertTrue(uploadIndexes.allSatisfy { $0 < firstRename }, operations.joined(separator: "\n"))
        XCTAssertLessThan(firstRename, releasePatch)
        XCTAssertLessThan(releasePatch, tagPush)
        XCTAssertLessThan(tagPush, firstDelete)

        let canonicalRenames = operations.filter { operation in
            operation.hasPrefix("rename:") &&
                !operation.contains("quill-cowork-rollback-")
        }
        XCTAssertEqual(canonicalRenames.last?.split(separator: ":").last.map(String.init), "latest-tester-build.json")
        XCTAssertFalse(operations.contains { $0.contains("--clobber") })
    }

    func testFailuresRestorePreviousReleaseAndTag() throws {
        for failure in ["upload", "patch-asset", "patch-release", "push-tag"] {
            let result = try runPublisher(failure: failure)

            XCTAssertNotEqual(result.exitCode, 0, "\(failure) unexpectedly succeeded")
            XCTAssertTrue(
                result.output.contains("Restored the previous tester release"),
                "\(failure): \(result.output)"
            )
            XCTAssertEqual(result.state["tag"] as? String, oldCommit, failure)
            let release = try release(from: result.state)
            XCTAssertEqual(release["target_commitish"] as? String, oldCommit, failure)
            XCTAssertEqual(release["name"] as? String, "Previous tester", failure)
            XCTAssertEqual(release["body"] as? String, "Previous notes\n", failure)
            XCTAssertEqual(
                try assetNames(in: release),
                ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "obsolete.txt"],
                failure
            )
            let assets = try assets(in: release)
            XCTAssertEqual(
                assets.compactMap { $0["digest"] as? String }.sorted(),
                ["sha256:old-app", "sha256:old-manifest", "sha256:old-obsolete"],
                failure
            )
            XCTAssertFalse(
                try assetNames(in: release).contains { $0.hasPrefix("quill-cowork-") },
                failure
            )
        }
    }

    func testTransientRollbackAssetDeletionRetriesAfterCommit() throws {
        let result = try runPublisher(failure: "delete-asset")

        XCTAssertEqual(result.exitCode, 0, result.output)
        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        XCTAssertEqual(operations.filter { $0 == "failure:delete-asset" }.count, 1)
        XCTAssertEqual(
            try assetNames(in: release(from: result.state)),
            ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "new-evidence.json"]
        )
    }

    func testTransientReleaseReadRetriesBeforeAnyMutation() throws {
        let result = try runPublisher(failure: "get-release-transient")

        XCTAssertEqual(result.exitCode, 0, result.output)
        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        XCTAssertEqual(operations.filter { $0 == "failure:get-release-transient" }.count, 1)
        XCTAssertEqual(operations.first, "failure:get-release-transient")
        XCTAssertEqual(result.state["tag"] as? String, newCommit)
    }

    func testTemporaryReleaseNotFoundDuringCandidateUploadRetriesSafely() throws {
        let result = try runPublisher(failure: "upload-release-not-found")

        XCTAssertEqual(result.exitCode, 0, result.output)
        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        XCTAssertEqual(operations.filter { $0 == "failure:upload-release-not-found" }.count, 1)
        XCTAssertEqual(operations.filter { $0.hasPrefix("upload:") }.count, 3)
        XCTAssertEqual(
            try assetNames(in: release(from: result.state)),
            ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "new-evidence.json"]
        )
    }

    func testLostCandidateUploadResponseAcceptsOnlyExactRetainedAsset() throws {
        let result = try runPublisher(failure: "upload-transient-after-mutation")

        XCTAssertEqual(result.exitCode, 0, result.output)
        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        XCTAssertEqual(
            operations.filter { $0 == "failure:upload-transient-after-mutation" }.count,
            1
        )
        XCTAssertEqual(operations.filter { $0.hasPrefix("upload:") }.count, 3)
        XCTAssertEqual(
            try assetNames(in: release(from: result.state)),
            ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "new-evidence.json"]
        )
    }

    func testLostUploadResponseWithConflictingRemoteAssetRestoresPreviousRelease() throws {
        let result = try runPublisher(failure: "upload-transient-after-conflicting-mutation")

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("conflicting metadata"), result.output)
        XCTAssertTrue(result.output.contains("Restored the previous tester release"), result.output)
        XCTAssertEqual(result.state["tag"] as? String, oldCommit)
        XCTAssertEqual(
            try assetNames(in: release(from: result.state)),
            ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "obsolete.txt"]
        )
    }

    func testPersistentTransientReleaseFailureExhaustsBoundedRetriesWithoutMutation() throws {
        let result = try runPublisher(
            failure: "get-release-transient",
            failureCount: 5
        )

        XCTAssertNotEqual(result.exitCode, 0)
        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        XCTAssertEqual(operations.count, 5)
        XCTAssertTrue(operations.allSatisfy { $0 == "failure:get-release-transient" })
        XCTAssertEqual(result.state["tag"] as? String, oldCommit)
    }

    func testTransientIdempotentRemoteMutationsRetry() throws {
        for failure in ["patch-asset-transient", "patch-release-transient", "push-tag-transient"] {
            let result = try runPublisher(failure: failure)

            XCTAssertEqual(result.exitCode, 0, "\(failure): \(result.output)")
            let operations = try XCTUnwrap(result.state["operations"] as? [String])
            XCTAssertEqual(
                operations.filter { $0 == "failure:\(failure)" }.count,
                1,
                failure
            )
            XCTAssertEqual(result.state["tag"] as? String, newCommit, failure)
        }
    }

    func testLostDeleteResponseRecognizesCompletedCleanup() throws {
        let result = try runPublisher(failure: "delete-asset-after-mutation")

        XCTAssertEqual(result.exitCode, 0, result.output)
        let operations = try XCTUnwrap(result.state["operations"] as? [String])
        XCTAssertEqual(operations.filter { $0 == "failure:delete-asset-after-mutation" }.count, 1)
        XCTAssertEqual(operations.filter { $0.hasPrefix("delete:") }.count, 3)
        XCTAssertEqual(
            try assetNames(in: release(from: result.state)),
            ["Quill-Cowork-macOS-arm64.zip", "latest-tester-build.json", "new-evidence.json"]
        )
    }

    func testUnsafeInputsFailBeforeGitHubMutation() throws {
        let result = try runPublisher(commit: "short")

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Commit must be a full lowercase SHA-1"), result.output)
        XCTAssertEqual(result.state["operations"] as? [String], [])
        XCTAssertEqual(result.state["tag"] as? String, oldCommit)
    }

    private struct PublisherResult {
        var exitCode: Int32
        var output: String
        var state: [String: Any]
    }

    private func runPublisher(
        failure: String? = nil,
        failureCount: Int = 1,
        commit: String? = nil
    ) throws -> PublisherResult {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-transactional-publication-tests")
            .appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("bin")
        let assetsDirectory = root.appendingPathComponent("assets")
        let stateURL = root.appendingPathComponent("state.json")
        let notesURL = root.appendingPathComponent("release-notes.md")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("new app".utf8).write(
            to: assetsDirectory.appendingPathComponent("Quill-Cowork-macOS-arm64.zip")
        )
        try Data(#"{"build":"new"}"#.utf8).write(
            to: assetsDirectory.appendingPathComponent("latest-tester-build.json")
        )
        try Data(#"{"withinBudget":true}"#.utf8).write(
            to: assetsDirectory.appendingPathComponent("new-evidence.json")
        )
        try "New release notes\n".write(to: notesURL, atomically: true, encoding: .utf8)

        let initialState: [String: Any] = [
            "tag": oldCommit,
            "localTag": oldCommit,
            "nextAssetID": 100,
            "operations": [],
            "failures": failure.map { [$0: failureCount] } ?? [:],
            "release": [
                "id": 77,
                "tag_name": "tester-latest",
                "target_commitish": oldCommit,
                "name": "Previous tester",
                "body": "Previous notes\n",
                "draft": false,
                "prerelease": true,
                "immutable": false,
                "assets": [
                    remoteAsset(id: 1, name: "Quill-Cowork-macOS-arm64.zip", size: 7, digest: "sha256:old-app"),
                    remoteAsset(id: 2, name: "latest-tester-build.json", size: 18, digest: "sha256:old-manifest"),
                    remoteAsset(id: 3, name: "obsolete.txt", size: 8, digest: "sha256:old-obsolete")
                ]
            ]
        ]
        let stateData = try JSONSerialization.data(withJSONObject: initialState, options: [.sortedKeys])
        try stateData.write(to: stateURL)

        try writeExecutable(fakeGitHub, to: bin.appendingPathComponent("gh"))
        try writeExecutable(fakeGit, to: bin.appendingPathComponent("git"))

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            Self.packageRoot().appendingPathComponent("scripts/publish-tester-release.py").path,
            "--assets-dir", assetsDirectory.path,
            "--notes-file", notesURL.path,
            "--repo", "Lore-Hex/QuillCode",
            "--commit", commit ?? newCommit,
            "--run-id", "1234",
            "--retry-delay-seconds", "0"
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):\(environment["PATH"] ?? "")"
        environment["FAKE_PUBLICATION_STATE"] = stateURL.path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment

        try process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let finalData = try Data(contentsOf: stateURL)
        let finalState = try XCTUnwrap(
            JSONSerialization.jsonObject(with: finalData) as? [String: Any]
        )
        return PublisherResult(
            exitCode: process.terminationStatus,
            output: output,
            state: finalState
        )
    }

    private func remoteAsset(id: Int, name: String, size: Int, digest: String) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "size": size,
            "digest": digest,
            "state": "uploaded"
        ]
    }

    private func release(from state: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(state["release"] as? [String: Any])
    }

    private func assets(in release: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(release["assets"] as? [[String: Any]])
    }

    private func assetNames(in release: [String: Any]) throws -> [String] {
        try assets(in: release).compactMap { $0["name"] as? String }.sorted()
    }

    private func writeExecutable(_ source: String, to url: URL) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private var fakeGitHub: String {
        #"""
        #!/usr/bin/env python3
        import hashlib
        import json
        import os
        from pathlib import Path
        import sys

        state_path = Path(os.environ["FAKE_PUBLICATION_STATE"])

        def load():
            return json.loads(state_path.read_text())

        def save(state):
            temporary = state_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, sort_keys=True))
            temporary.replace(state_path)

        def record(state, operation):
            state["operations"].append(operation)

        def fail_if_requested(state, point):
            remaining = state.get("failures", {}).get(point, 0)
            if remaining > 0:
                state["failures"][point] = remaining - 1
                record(state, "failure:" + point)
                save(state)
                print("injected failure: " + point, file=sys.stderr)
                raise SystemExit(42)

        def fail_with_diagnostic_if_requested(state, point, diagnostic):
            remaining = state.get("failures", {}).get(point, 0)
            if remaining > 0:
                state["failures"][point] = remaining - 1
                record(state, "failure:" + point)
                save(state)
                print(diagnostic, file=sys.stderr)
                raise SystemExit(42)

        def asset_by_id(state, identifier):
            for asset in state["release"]["assets"]:
                if asset["id"] == identifier:
                    return asset
            print("asset not found", file=sys.stderr)
            raise SystemExit(44)

        args = sys.argv[1:]
        state = load()
        if args[:1] == ["api"]:
            method = args[args.index("--method") + 1]
            endpoint = next(value for value in args if value.startswith("repos/"))
            if method == "GET" and "/releases/tags/" in endpoint:
                fail_with_diagnostic_if_requested(
                    state,
                    "get-release-transient",
                    "tls: failed to verify certificate: x509: certificate signed by unknown authority"
                )
                record(state, "get-release")
                save(state)
                print(json.dumps(state["release"], sort_keys=True))
                raise SystemExit(0)
            if "/releases/assets/" in endpoint:
                identifier = int(endpoint.rsplit("/", 1)[1])
                if method == "PATCH":
                    fail_with_diagnostic_if_requested(
                        state,
                        "patch-asset-transient",
                        "tls: failed to verify certificate: x509: certificate signed by unknown authority"
                    )
                    fail_if_requested(state, "patch-asset")
                    requested = args[args.index("-f") + 1]
                    name = requested.split("=", 1)[1]
                    asset = asset_by_id(state, identifier)
                    record(state, "rename:{}:{}".format(asset["name"], name))
                    asset["name"] = name
                    save(state)
                    print(json.dumps(asset, sort_keys=True))
                    raise SystemExit(0)
                if method == "DELETE":
                    fail_if_requested(state, "delete-asset")
                    asset = asset_by_id(state, identifier)
                    record(state, "delete:" + asset["name"])
                    state["release"]["assets"] = [
                        value for value in state["release"]["assets"]
                        if value["id"] != identifier
                    ]
                    save(state)
                    fail_with_diagnostic_if_requested(
                        state,
                        "delete-asset-after-mutation",
                        "tls: failed to verify certificate: x509: certificate signed by unknown authority"
                    )
                    raise SystemExit(0)
            if method == "PATCH" and "/releases/" in endpoint:
                fail_with_diagnostic_if_requested(
                    state,
                    "patch-release-transient",
                    "tls: failed to verify certificate: x509: certificate signed by unknown authority"
                )
                fail_if_requested(state, "patch-release")
                payload_path = Path(args[args.index("--input") + 1])
                payload = json.loads(payload_path.read_text())
                for key in ["tag_name", "target_commitish", "name", "body", "draft", "prerelease"]:
                    state["release"][key] = payload[key]
                record(state, "patch-release")
                save(state)
                print(json.dumps(state["release"], sort_keys=True))
                raise SystemExit(0)
        if args[:2] == ["release", "upload"]:
            fail_with_diagnostic_if_requested(
                state,
                "upload-release-not-found",
                "release not found"
            )
            fail_if_requested(state, "upload")
            path = Path(args[3])
            data = path.read_bytes()
            asset = {
                "id": state["nextAssetID"],
                "name": path.name,
                "size": len(data),
                "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
                "state": "uploaded"
            }
            if state.get("failures", {}).get(
                "upload-transient-after-conflicting-mutation",
                0
            ) > 0:
                asset["digest"] = "sha256:conflicting-remote-content"
            state["nextAssetID"] += 1
            state["release"]["assets"].append(asset)
            record(state, "upload:" + path.name)
            save(state)
            fail_with_diagnostic_if_requested(
                state,
                "upload-transient-after-conflicting-mutation",
                "tls: failed to verify certificate: x509: certificate signed by unknown authority"
            )
            fail_with_diagnostic_if_requested(
                state,
                "upload-transient-after-mutation",
                "tls: failed to verify certificate: x509: certificate signed by unknown authority"
            )
            raise SystemExit(0)
        print("unexpected gh invocation: " + " ".join(args), file=sys.stderr)
        raise SystemExit(49)
        """#
    }

    private var fakeGit: String {
        #"""
        #!/usr/bin/env python3
        import json
        import os
        from pathlib import Path
        import sys

        state_path = Path(os.environ["FAKE_PUBLICATION_STATE"])

        def load():
            return json.loads(state_path.read_text())

        def save(state):
            temporary = state_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, sort_keys=True))
            temporary.replace(state_path)

        def fail_if_requested(state, point):
            remaining = state.get("failures", {}).get(point, 0)
            if remaining > 0:
                state["failures"][point] = remaining - 1
                state["operations"].append("failure:" + point)
                save(state)
                print("injected failure: " + point, file=sys.stderr)
                raise SystemExit(42)

        def fail_transient_if_requested(state, point):
            remaining = state.get("failures", {}).get(point, 0)
            if remaining > 0:
                state["failures"][point] = remaining - 1
                state["operations"].append("failure:" + point)
                save(state)
                print(
                    "tls: failed to verify certificate: x509: certificate signed by unknown authority",
                    file=sys.stderr
                )
                raise SystemExit(42)

        args = sys.argv[1:]
        state = load()
        if args[:1] == ["config"]:
            raise SystemExit(0)
        if args[:2] == ["ls-remote", "--refs"]:
            if state.get("tag"):
                print("{}\trefs/tags/tester-latest".format(state["tag"]))
            raise SystemExit(0)
        if args[:2] == ["tag", "-f"]:
            state["localTag"] = args[3]
            state["operations"].append("local-tag:" + args[3])
            save(state)
            raise SystemExit(0)
        if args[:2] == ["tag", "-d"]:
            state["localTag"] = None
            save(state)
            raise SystemExit(0)
        if args[:2] == ["push", "origin"]:
            if args[2].startswith(":"):
                state["tag"] = None
                state["operations"].append("delete-tag")
                save(state)
                raise SystemExit(0)
            fail_transient_if_requested(state, "push-tag-transient")
            fail_if_requested(state, "push-tag")
            state["tag"] = state["localTag"]
            state["operations"].append("push-tag:" + state["tag"])
            save(state)
            raise SystemExit(0)
        print("unexpected git invocation: " + " ".join(args), file=sys.stderr)
        raise SystemExit(49)
        """#
    }
}
