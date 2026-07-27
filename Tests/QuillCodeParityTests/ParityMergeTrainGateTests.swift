import XCTest

final class ParityMergeTrainGateTests: QuillCodeParityTestCase {
    func testBehindBranchesDoNotUseActionTokenUpdatesByDefault() throws {
        let result = try runMergeTrain(updateBehindBranches: nil)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("PR #42 is behind main; waiting for the branch author to rebase or merge main and push."))
        XCTAssertTrue(result.output.contains("Automatic branch updates are disabled by default"))
        XCTAssertFalse(result.ghLog.contains("update-branch"), "The default train must not mutate behind branches with GITHUB_TOKEN.")
    }

    func testBehindBranchUpdateRequiresExplicitOptIn() throws {
        let result = try runMergeTrain(updateBehindBranches: "true")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("PR #42 is behind main; updating branch and waiting for fresh CI."))
        XCTAssertTrue(result.ghLog.contains("pr update-branch 42 --repo Lore-Hex/QuillCode"))
    }

    func testMergedPullRequestDispatchesAllConfiguredPostMergeWorkflows() throws {
        let result = try runMergeTrain(
            pullRequestJSON: readyCleanPullRequestJSON,
            postMergeWorkflows: "ci.yml download-builds.yml"
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.ghLog.contains("pr merge 42 --repo Lore-Hex/QuillCode --squash --delete-branch"))
        XCTAssertTrue(result.ghLog.contains("workflow run ci.yml --repo Lore-Hex/QuillCode --ref main"))
        XCTAssertTrue(result.ghLog.contains("workflow run download-builds.yml --repo Lore-Hex/QuillCode --ref main"))
    }

    private struct MergeTrainResult {
        let exitCode: Int32
        let output: String
        let ghLog: String
    }

    private func runMergeTrain(
        pullRequestJSON: String? = nil,
        updateBehindBranches: String? = nil,
        postMergeWorkflows: String? = nil
    ) throws -> MergeTrainResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-merge-train-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let ghLogURL = temporaryDirectory.appendingPathComponent("gh.log")
        let prJSONURL = temporaryDirectory.appendingPathComponent("prs.json")
        let fakeGHURL = binDirectory.appendingPathComponent("gh")

        try (pullRequestJSON ?? readyBehindPullRequestJSON).write(to: prJSONURL, atomically: true, encoding: .utf8)
        try fakeGHScript.write(to: fakeGHURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGHURL.path)

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.packageRoot().appendingPathComponent("scripts/merge-train.sh").path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["GITHUB_REPOSITORY"] = "Lore-Hex/QuillCode"
        environment["MERGE_TRAIN_GH_LOG"] = ghLogURL.path
        environment["MERGE_TRAIN_PR_JSON"] = prJSONURL.path
        if let updateBehindBranches {
            environment["MERGE_TRAIN_UPDATE_BEHIND_BRANCHES"] = updateBehindBranches
        } else {
            environment.removeValue(forKey: "MERGE_TRAIN_UPDATE_BEHIND_BRANCHES")
        }
        if let postMergeWorkflows {
            environment["MERGE_TRAIN_POST_MERGE_WORKFLOWS"] = postMergeWorkflows
        } else {
            environment.removeValue(forKey: "MERGE_TRAIN_POST_MERGE_WORKFLOWS")
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ghLog = (try? String(contentsOf: ghLogURL, encoding: .utf8)) ?? ""
        return MergeTrainResult(exitCode: process.terminationStatus, output: output, ghLog: ghLog)
    }

    private var readyBehindPullRequestJSON: String {
        """
        [
          {
            "number": 42,
            "title": "Ready behind PR",
            "url": "https://github.com/Lore-Hex/QuillCode/pull/42",
            "isDraft": false,
            "createdAt": "2026-06-29T00:00:00Z",
            "mergeStateStatus": "BEHIND",
            "statusCheckRollup": [
              {"name": "swift", "status": "COMPLETED", "conclusion": "SUCCESS"},
              {"name": "linux-swift", "status": "COMPLETED", "conclusion": "SUCCESS"},
              {"name": "smoke", "status": "COMPLETED", "conclusion": "SUCCESS"}
            ],
            "labels": [{"name": "merge-train"}],
            "headRefName": "feature",
            "headRepositoryOwner": {"login": "Lore-Hex"}
          }
        ]
        """
    }

    private var readyCleanPullRequestJSON: String {
        """
        [
          {
            "number": 42,
            "title": "Ready clean PR",
            "url": "https://github.com/Lore-Hex/QuillCode/pull/42",
            "isDraft": false,
            "createdAt": "2026-06-29T00:00:00Z",
            "mergeStateStatus": "CLEAN",
            "statusCheckRollup": [
              {"name": "swift", "status": "COMPLETED", "conclusion": "SUCCESS"},
              {"name": "linux-swift", "status": "COMPLETED", "conclusion": "SUCCESS"},
              {"name": "smoke", "status": "COMPLETED", "conclusion": "SUCCESS"}
            ],
            "labels": [{"name": "merge-train"}],
            "headRefName": "feature",
            "headRepositoryOwner": {"login": "Lore-Hex"}
          }
        ]
        """
    }

    private var fakeGHScript: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\\n' "$*" >> "${MERGE_TRAIN_GH_LOG:?}"
        if [[ "$1" == "pr" && "$2" == "list" ]]; then
          cat "${MERGE_TRAIN_PR_JSON:?}"
          exit 0
        fi
        if [[ "$1" == "pr" && "$2" == "update-branch" ]]; then
          exit 0
        fi
        if [[ "$1" == "pr" && "$2" == "merge" ]]; then
          exit 0
        fi
        if [[ "$1" == "workflow" && "$2" == "run" ]]; then
          exit 0
        fi
        echo "unexpected gh invocation: $*" >&2
        exit 9
        """
    }
}
