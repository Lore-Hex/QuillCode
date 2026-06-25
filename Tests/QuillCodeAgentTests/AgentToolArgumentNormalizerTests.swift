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
    }
}
