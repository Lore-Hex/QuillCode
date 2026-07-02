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

    func testCanonicalArgumentsNormalizeFileSearchAliases() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.fileSearch.name,
            in: [
                "arguments": [
                    "term": "AgentRunner",
                    "directory": "Sources",
                    "limit": 5
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["query"] as? String, "AgentRunner")
        XCTAssertEqual(arguments["path"] as? String, "Sources")
        XCTAssertEqual(arguments["maxResults"] as? Int, 5)
        XCTAssertNil(arguments["term"])
        XCTAssertNil(arguments["directory"])
        XCTAssertNil(arguments["limit"])
    }

    func testCanonicalArgumentsNormalizeFileListAliases() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.fileList.name,
            in: [
                "arguments": [
                    "directory": "Sources",
                    "hidden": true,
                    "limit": 10
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["path"] as? String, "Sources")
        XCTAssertEqual(arguments["includeHidden"] as? Bool, true)
        XCTAssertEqual(arguments["maxEntries"] as? Int, 10)
        XCTAssertNil(arguments["directory"])
        XCTAssertNil(arguments["hidden"])
        XCTAssertNil(arguments["limit"])
        XCTAssertTrue(AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
            for: ToolDefinition.fileList.name,
            arguments: [:]
        ))
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

    func testCanonicalArgumentsNormalizePullRequestListAliases() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.gitPullRequestList.name,
            in: [
                "arguments": [
                    "status": "merged",
                    "count": 12
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["state"] as? String, "merged")
        XCTAssertEqual(arguments["limit"] as? Int, 12)
        XCTAssertNil(arguments["status"])
        XCTAssertNil(arguments["count"])
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

    func testCanonicalArgumentsNormalizePullRequestLifecycleAliasesWithoutBodyCoupling() {
        let arguments = AgentToolArgumentNormalizer.canonicalArguments(
            for: ToolDefinition.gitPullRequestLifecycle.name,
            in: [
                "arguments": [
                    "pr": "42",
                    "state": "re-open",
                    "message": "This must not become a body argument."
                ]
            ],
            sourceText: ""
        )

        XCTAssertEqual(arguments["selector"] as? String, "42")
        XCTAssertEqual(arguments["action"] as? String, "re-open")
        XCTAssertNil(arguments["body"])
        XCTAssertNil(arguments["pr"])
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
        XCTAssertFalse(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.fileSearch.name,
                arguments: ["path": "Sources"]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.fileSearch.name,
                arguments: ["query": "AgentRunner"]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.gitPullRequestList.name,
                arguments: [:]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.gitPullRequestReviewThreads.name,
                arguments: [:]
            )
        )
        XCTAssertFalse(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.gitPullRequestLifecycle.name,
                arguments: ["selector": "42"]
            )
        )
        XCTAssertTrue(
            AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: ToolDefinition.gitPullRequestLifecycle.name,
                arguments: ["action": "close"]
            )
        )
    }
}
