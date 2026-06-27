import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class TrustedRouterActionParserTests: XCTestCase {
    func testActionParserParsesShellTool() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}
        """)
        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, "host.shell.run")
        XCTAssertTrue(call.argumentsJSON.contains("whoami"))
    }

    func testActionParserRejectsEmptyShellArguments() {
        XCTAssertThrowsError(try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.shell.run","arguments":{}}
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("empty argument"))
        }
    }

    func testActionParserNormalizesShellCommandAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.shell.run","arguments":{"command":"whoami"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertTrue(call.argumentsJSON.contains(#""cmd":"whoami""#))
        XCTAssertFalse(call.argumentsJSON.contains(#""command""#))
    }

    func testActionParserHoistsTopLevelShellCommandAlias() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool_call","tool":"host.shell.run","command":"git status --short"}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertTrue(call.argumentsJSON.contains(#""cmd":"git status --short""#))
    }

    func testActionParserExtractsActionObjectFromProse() throws {
        let action = try AgentActionJSONParser.parse("""
        I will run the command now.
        {"type":"tool","name":"host.shell.run","arguments":{"cmd":"whoami"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertTrue(call.argumentsJSON.contains(#""cmd":"whoami""#))
    }

    func testActionParserRecoversExplicitBacktickedShellCommandFromProse() throws {
        let action = try AgentActionJSONParser.parse("I'll run `whoami` on the device.")

        guard case .tool(let call) = action else {
            return XCTFail("Expected recovered shell tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(try arguments.requiredString("cmd"), "whoami")
    }

    func testActionParserRecoversCurlyApostropheExecutionIntent() throws {
        let action = try AgentActionJSONParser.parse("I’ll check `df -h /` now.")

        guard case .tool(let call) = action else {
            return XCTFail("Expected recovered shell tool action")
        }
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(try arguments.requiredString("cmd"), "df -h /")
    }

    func testActionParserRepairsEmptyShellArgumentsFromExplicitNearbyCommand() throws {
        let action = try AgentActionJSONParser.parse("""
        I'll execute `command -v openclaw || which openclaw || echo 'not found'`.
        {"type":"tool","name":"host.shell.run","arguments":{}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected repaired shell tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(
            try arguments.requiredString("cmd"),
            "command -v openclaw || which openclaw || echo 'not found'"
        )
    }

    func testActionParserDoesNotRecoverPassiveBacktickedTextAsCommand() {
        XCTAssertThrowsError(try AgentActionJSONParser.parse("You can use `whoami` if you want.")) { error in
            XCTAssertTrue(String(describing: error).contains("valid QuillCode action JSON object"))
        }
    }

    func testActionParserDoesNotRecoverNegativeBacktickedCommandIntent() {
        XCTAssertThrowsError(try AgentActionJSONParser.parse("I will not run `rm -rf /`.")) { error in
            XCTAssertTrue(String(describing: error).contains("valid QuillCode action JSON object"))
        }
    }

    func testActionParserKeepsMalformedTextActionable() {
        XCTAssertThrowsError(try AgentActionJSONParser.parse("I will do it, but no JSON.")) { error in
            XCTAssertTrue(String(describing: error).contains("valid QuillCode action JSON object"))
        }
    }

    func testActionParserNormalizesFileWriteAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","toolName":"host.file.write","args":{"filename":"hello.txt","text":"hello world\\n"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.fileWrite.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(try arguments.requiredString("path"), "hello.txt")
        XCTAssertEqual(try arguments.requiredString("content"), "hello world\n")
        XCTAssertFalse(call.argumentsJSON.contains(#""filename""#))
        XCTAssertFalse(call.argumentsJSON.contains(#""text""#))
    }

    func testActionParserNormalizesSayMessageAlias() throws {
        let action = try AgentActionJSONParser.parse(#"{"type":"say","message":"done"}"#)

        XCTAssertEqual(action, .say("done"))
    }

    func testActionParserNormalizesPullRequestReviewAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.review","arguments":{"pr":"42","decision":"approve","message":"Looks good."}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReview.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.string("action"), "approve")
        XCTAssertEqual(arguments.string("body"), "Looks good.")
    }

    func testActionParserNormalizesPullRequestMergeAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.merge","arguments":{"pr":"42","strategy":"rebase","auto":true,"deleteBranch":true}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestMerge.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.string("method"), "rebase")
        XCTAssertEqual(arguments.bool("auto"), true)
        XCTAssertEqual(arguments.bool("deleteBranch"), true)
    }

    func testActionParserNormalizesPullRequestCheckoutAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.checkout","arguments":{"pr":"42","localBranch":"review/pr-42"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestCheckout.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.string("branch"), "review/pr-42")
    }

    func testActionParserNormalizesPullRequestReviewerAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.reviewers","arguments":{"pr":"42","reviewers":[" alice ",""," myorg/team-name "],"removeReviewers":"bob"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReviewers.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.stringArray("add"), ["alice", "myorg/team-name"])
        XCTAssertEqual(arguments.stringArray("remove"), ["bob"])
    }

    func testActionParserNormalizesPullRequestLabelAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.labels","arguments":{"pr":"42","labels":[" merge-train ",""," needs review "],"removeLabels":"blocked"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestLabels.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.stringArray("add"), ["merge-train", "needs review"])
        XCTAssertEqual(arguments.stringArray("remove"), ["blocked"])
    }

    func testActionParserNormalizesPullRequestReviewReplyAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.review_reply","arguments":{"pr":"42","comment_id":99,"message":"Updated this."}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReviewReply.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.int("commentId"), 99)
        XCTAssertEqual(arguments.string("body"), "Updated this.")
    }

    func testActionParserNormalizesPullRequestReviewThreadAliases() throws {
        let action = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.review_thread","arguments":{"thread_id":"PRRT_kwDOExample","state":"resolve"}}
        """)

        guard case .tool(let call) = action else {
            return XCTFail("Expected tool action")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReviewThread.name)
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(arguments.string("threadId"), "PRRT_kwDOExample")
        XCTAssertEqual(arguments.string("action"), "resolve")
    }

    func testActionParserAllowsNoArgumentTools() throws {
        let gitAction = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.status","arguments":{}}
        """)
        guard case .tool(let gitCall) = gitAction else {
            return XCTFail("Expected git status tool action")
        }
        XCTAssertEqual(gitCall.name, ToolDefinition.gitStatus.name)
        XCTAssertEqual(gitCall.argumentsJSON, "{}")

        let screenshotAction = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.computer.screenshot","arguments":{}}
        """)
        guard case .tool(let screenshotCall) = screenshotAction else {
            return XCTFail("Expected screenshot tool action")
        }
        XCTAssertEqual(screenshotCall.name, "host.computer.screenshot")
        XCTAssertEqual(screenshotCall.argumentsJSON, "{}")

        let browserAction = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.browser.inspect","arguments":{}}
        """)
        guard case .tool(let browserCall) = browserAction else {
            return XCTFail("Expected browser inspection tool action")
        }
        XCTAssertEqual(browserCall.name, ToolDefinition.browserInspect.name)
        XCTAssertEqual(browserCall.argumentsJSON, "{}")

        let browserOpenAction = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.browser.open","arguments":{"address":"localhost:5173"}}
        """)
        guard case .tool(let browserOpenCall) = browserOpenAction else {
            return XCTFail("Expected browser open tool action")
        }
        XCTAssertEqual(browserOpenCall.name, ToolDefinition.browserOpen.name)
        XCTAssertEqual(browserOpenCall.argumentsJSON, ToolArguments.json(["url": "localhost:5173"]))

        let mergeAction = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.merge","arguments":{}}
        """)
        guard case .tool(let mergeCall) = mergeAction else {
            return XCTFail("Expected PR merge tool action")
        }
        XCTAssertEqual(mergeCall.name, ToolDefinition.gitPullRequestMerge.name)
        XCTAssertEqual(mergeCall.argumentsJSON, "{}")

        let checkoutAction = try AgentActionJSONParser.parse("""
        {"type":"tool","name":"host.git.pr.checkout","arguments":{}}
        """)
        guard case .tool(let checkoutCall) = checkoutAction else {
            return XCTFail("Expected PR checkout tool action")
        }
        XCTAssertEqual(checkoutCall.name, ToolDefinition.gitPullRequestCheckout.name)
        XCTAssertEqual(checkoutCall.argumentsJSON, "{}")
    }

    func testActionParserParsesSay() throws {
        let action = try AgentActionJSONParser.parse(#"{"type":"say","text":"hello"}"#)
        XCTAssertEqual(action, .say("hello"))
    }
}
