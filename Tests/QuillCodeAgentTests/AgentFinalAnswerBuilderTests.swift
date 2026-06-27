import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentFinalAnswerBuilderTests: XCTestCase {
    func testShellWhoamiAnswerIsSpecific() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "whoami"])
            ),
            result: ToolResult(ok: true, stdout: "quill\n")
        )

        XCTAssertEqual(answer, "You are `quill` in this workspace.")
    }

    func testOpenClawDiscoverySummarizesMissingBinary() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "command -v openclaw || which openclaw || echo 'not found'"
                ])
            ),
            result: ToolResult(ok: true, stdout: "not found\n")
        )

        XCTAssertEqual(answer, "openclaw is not installed or is not on PATH.")
    }

    func testWorktreePruneDryRunReportsNoStaleRecords() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.gitWorktreePrune.name,
                argumentsJSON: ToolArguments.json(["dryRun": true, "verbose": true])
            ),
            result: ToolResult(ok: true)
        )

        XCTAssertEqual(answer, "No stale worktree records found.")
    }

    func testWorktreePruneDryRunReportsStaleRecordsAndCleanupCommand() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.gitWorktreePrune.name,
                argumentsJSON: ToolArguments.json(["dryRun": true, "verbose": true])
            ),
            result: ToolResult(
                ok: true,
                stdout: "Removing ../quillcode-old: gitdir file points to non-existent location\n"
            )
        )

        XCTAssertTrue(answer.contains("Found 1 stale worktree record."))
        XCTAssertTrue(answer.contains("Run `/worktree prune` to remove it."))
        XCTAssertTrue(answer.contains("../quillcode-old"))
    }

    func testWorktreePruneReportsRemovedRecords() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.gitWorktreePrune.name,
                argumentsJSON: ToolArguments.json(["dryRun": false, "verbose": true])
            ),
            result: ToolResult(
                ok: true,
                stdout: """
                Removing ../quillcode-old: gitdir file points to non-existent location
                Removing ../quillcode-older: gitdir file points to non-existent location
                """
            )
        )

        XCTAssertTrue(answer.contains("Pruned 2 stale worktree records."))
        XCTAssertTrue(answer.contains("../quillcode-old"))
        XCTAssertTrue(answer.contains("../quillcode-older"))
    }

    func testPullRequestReviewThreadsAnswerSummarizesGraphQLOutput() {
        let output = """
        {
          "data": {
            "repository": {
              "pullRequest": {
                "reviewThreads": {
                  "nodes": [
                    {
                      "id": "PRRT_unresolved",
                      "isResolved": false,
                      "isOutdated": false,
                      "path": "Sources/App.swift",
                      "line": 24,
                      "startLine": 20,
                      "comments": {
                        "nodes": [
                          {
                            "id": "PRRC_node",
                            "databaseId": 12345,
                            "body": "This should use the shared command descriptor.",
                            "author": { "login": "reviewer" }
                          }
                        ]
                      }
                    },
                    {
                      "id": "PRRT_resolved",
                      "isResolved": true,
                      "isOutdated": true,
                      "path": "Tests/AppTests.swift",
                      "line": 42,
                      "startLine": null,
                      "comments": { "nodes": [] }
                    }
                  ]
                }
              }
            }
          }
        }
        """

        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.gitPullRequestReviewThreads.name,
                argumentsJSON: ToolArguments.json([:])
            ),
            result: ToolResult(ok: true, stdout: output)
        )

        XCTAssertTrue(answer.contains("Found 2 review threads: 1 unresolved, 1 resolved."))
        XCTAssertTrue(answer.contains("- unresolved `Sources/App.swift:20-24`: thread `PRRT_unresolved`; comment #12345 by reviewer"))
        XCTAssertTrue(answer.contains("This should use the shared command descriptor."))
        XCTAssertTrue(answer.contains("- resolved, outdated `Tests/AppTests.swift:42`: thread `PRRT_resolved`"))
    }

    func testPullRequestReviewThreadsAnswerHandlesEmptyGraphQLOutput() {
        let output = """
        {
          "data": {
            "repository": {
              "pullRequest": {
                "reviewThreads": { "nodes": [] }
              }
            }
          }
        }
        """

        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.gitPullRequestReviewThreads.name,
                argumentsJSON: ToolArguments.json([:])
            ),
            result: ToolResult(ok: true, stdout: output)
        )

        XCTAssertEqual(answer, "No pull request review threads found.")
    }

    func testLongOutputIsTruncatedWithToolCardHint() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "printf long-output"])
            ),
            result: ToolResult(ok: true, stdout: String(repeating: "x", count: 2_100))
        )

        XCTAssertTrue(answer.contains("[truncated in chat; full output is in the tool card]"))
        XCTAssertLessThan(answer.count, 2_100)
    }

    func testBrowserInspectFinalAnswerSummarizesPage() throws {
        let output = BrowserInspectionToolOutput(
            url: "http://localhost:5173",
            title: "Preview Page",
            status: "Preview ready",
            sourceLabel: "Local web app",
            inspectionDepth: .metadataOnly,
            summary: "Live DOM capture is not attached yet; QuillCode has URL metadata for this local page.",
            details: ["Host: localhost", "Scheme: HTTP", "Path: /"],
            outline: ["Page: localhost", "Path: /", "H1: Hero Preview"],
            textSnippet: "Hero Preview Buy now",
            comments: [
                .init(
                    url: "http://localhost:5173",
                    text: "Check the hero spacing",
                    createdAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )
        let call = ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}")

        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(output))
        )

        XCTAssertTrue(answer.contains("Inspected `Preview Page` at http://localhost:5173."))
        XCTAssertTrue(answer.contains("Inspection depth: Metadata only."))
        XCTAssertTrue(answer.contains("Outline: Page: localhost; Path: /; H1: Hero Preview."))
        XCTAssertTrue(answer.contains("Text: Hero Preview Buy now"))
        XCTAssertTrue(answer.contains("Browser comments: Check the hero spacing."))
    }

    func testApplyPatchFinalAnswerMentionsDiffRefreshFailure() throws {
        let call = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": "diff --git a/a b/a\n"])
        )

        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: "Patch applied.\n"),
            followUpReviewResult: ToolResult(ok: false, stderr: "not a git repository")
        )

        XCTAssertTrue(answer.contains("Patch applied"))
        XCTAssertTrue(answer.contains("could not refresh the review diff"))
        XCTAssertTrue(answer.contains("not a git repository"))
    }
}
