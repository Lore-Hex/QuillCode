import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentToolArgumentNormalizerTests: XCTestCase {
    func testCanonicalArgumentsNormalizeNestedStringAliasesFromRuleTable() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.fileWrite.name,
            in: [
                "args": [
                    "filename": "hello.txt",
                    "text": "hello world\n"
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["path"] as? String, "hello.txt")
        XCTAssertEqual(arguments["content"] as? String, "hello world\n")
        XCTAssertNil(arguments["filename"])
        XCTAssertNil(arguments["text"])
    }

    func testCanonicalArgumentsHoistTopLevelAliasesFromRuleTable() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.browserOpen.name,
            in: ["address": "localhost:5173"],
            sourceText: ""
        )

        XCTAssertEqual(arguments["url"] as? String, "localhost:5173")
        XCTAssertNil(arguments["address"])
    }

    func testCanonicalArgumentsDecodeStringifiedArgumentObjects() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.fileWrite.name,
            in: [
                "arguments": #"{"filename":"note.txt","text":"hello\n"}"#
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["path"] as? String, "note.txt")
        XCTAssertEqual(arguments["content"] as? String, "hello\n")
        XCTAssertNil(arguments["filename"])
        XCTAssertNil(arguments["text"])
    }

    func testCanonicalArgumentsNormalizePullRequestCollectionAliases() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.gitPullRequestReviewers.name,
            in: [
                "arguments": [
                    "pr": "42",
                    "reviewers": [" alice ", "", " myorg/team-name "],
                    "removeReviewers": "bob"
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["selector"] as? String, "42")
        XCTAssertEqual(arguments["add"] as? [String], ["alice", "myorg/team-name"])
        XCTAssertEqual(arguments["remove"] as? String, "bob")
        XCTAssertNil(arguments["pr"])
        XCTAssertNil(arguments["reviewers"])
        XCTAssertNil(arguments["removeReviewers"])
    }

    func testCanonicalArgumentsNormalizePullRequestReviewReplyAliases() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.gitPullRequestReviewReply.name,
            in: [
                "arguments": [
                    "pr": "42",
                    "comment_id": 99,
                    "message": "Updated this."
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["selector"] as? String, "42")
        XCTAssertEqual(arguments["commentId"] as? Int, 99)
        XCTAssertEqual(arguments["body"] as? String, "Updated this.")
        XCTAssertNil(arguments["comment_id"])
        XCTAssertNil(arguments["message"])
    }

    func testCanonicalArgumentsNormalizePullRequestReviewThreadAliases() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.gitPullRequestReviewThread.name,
            in: [
                "arguments": [
                    "thread_id": "PRRT_kwDOExample",
                    "state": "unresolve"
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["threadId"] as? String, "PRRT_kwDOExample")
        XCTAssertEqual(arguments["action"] as? String, "unresolve")
        XCTAssertNil(arguments["thread_id"])
        XCTAssertNil(arguments["state"])
    }

    func testShellCommandRecoveryRepairsEmptyArguments() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.shellRun.name,
            in: ["arguments": [:]],
            sourceText: "I'll run `whoami` now."
        )

        XCTAssertEqual(arguments["cmd"] as? String, "whoami")
    }

    func testMinimumRequiredArgumentsAllowKnownNoArgumentToolsOnly() {
        XCTAssertFalse(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.shellRun.name,
                arguments: [:]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.shellRun.name,
                arguments: ["cmd": "whoami"]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.browserInspect.name,
                arguments: [:]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.gitPullRequestReviewThreads.name,
                arguments: [:]
            )
        )
    }
}
