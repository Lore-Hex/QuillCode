import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectRunHookInvocationBuilderTests: XCTestCase {
    func testUserPromptSubmitInputMatchesStandardContract() throws {
        let root = try makeQuillCodeTestDirectory()
        let threadID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let turnID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let thread = ChatThread(
            id: threadID,
            mode: .auto,
            model: "deepseek/deepseek-v4-flash",
            messages: [ChatMessage(id: turnID, role: .user, content: "Review this")]
        )

        let json = try ProjectRunHookInvocationBuilder.inputJSON(
            timing: .beforeAgentRun,
            thread: thread,
            prompt: "Review this",
            workspaceRoot: root
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertTrue(json.hasSuffix("\n"))
        XCTAssertEqual(payload["session_id"] as? String, threadID.uuidString.lowercased())
        XCTAssertTrue(payload["transcript_path"] is NSNull)
        XCTAssertEqual(payload["cwd"] as? String, root.path)
        XCTAssertEqual(payload["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(payload["model"] as? String, "deepseek/deepseek-v4-flash")
        XCTAssertEqual(payload["turn_id"] as? String, turnID.uuidString.lowercased())
        XCTAssertEqual(payload["permission_mode"] as? String, "dontAsk")
        XCTAssertEqual(payload["prompt"] as? String, "Review this")
        XCTAssertNil(payload["stop_hook_active"])
        XCTAssertNil(payload["last_assistant_message"])
    }

    func testStopInputIncludesLastAssistantMessageAndPlanMode() throws {
        let root = try makeQuillCodeTestDirectory()
        let thread = ChatThread(
            mode: .plan,
            messages: [
                ChatMessage(role: .user, content: "Plan it"),
                ChatMessage(role: .assistant, content: "Here is the plan.")
            ]
        )

        let json = try ProjectRunHookInvocationBuilder.inputJSON(
            timing: .afterAgentRun,
            thread: thread,
            prompt: "Plan it",
            workspaceRoot: root
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(payload["permission_mode"] as? String, "plan")
        XCTAssertEqual(payload["stop_hook_active"] as? Bool, false)
        XCTAssertEqual(payload["last_assistant_message"] as? String, "Here is the plan.")
        XCTAssertNil(payload["prompt"])
    }

    func testStopInputMarksAutomaticContinuationActive() throws {
        let root = try makeQuillCodeTestDirectory()

        let json = try ProjectRunHookInvocationBuilder.inputJSON(
            timing: .afterAgentRun,
            thread: ChatThread(),
            prompt: "Continue",
            workspaceRoot: root,
            stopHookActive: true
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["stop_hook_active"] as? Bool, true)
    }

    func testInvocationAddsStandardPluginEnvironmentAndRedactableInput() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo")
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let dataBase = root.appendingPathComponent("private-plugin-data")
        let hook = ProjectRunHook(
            id: "plugin_hook:demo.userpromptsubmit.0.0",
            timing: .beforeAgentRun,
            title: "Demo",
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#UserPromptSubmit/0/0",
            command: "cat",
            pluginID: "plugin:demo",
            pluginRootRelativePath: ".quillcode/plugins/demo"
        )

        let invocation = try ProjectRunHookInvocationBuilder.build(
            hook: hook,
            thread: ChatThread(),
            prompt: "Private prompt",
            workspaceRoot: root,
            pluginDataBaseDirectory: dataBase
        )
        let arguments = try ToolArguments(invocation.call.argumentsJSON)
        let environment = try XCTUnwrap(arguments.stringDictionary("environment"))
        let dataPath = try XCTUnwrap(environment["PLUGIN_DATA"])

        XCTAssertEqual(environment["PLUGIN_ROOT"], pluginRoot.path)
        XCTAssertEqual(environment["CLAUDE_PLUGIN_ROOT"], pluginRoot.path)
        XCTAssertEqual(environment["CLAUDE_PLUGIN_DATA"], dataPath)
        XCTAssertTrue(dataPath.hasPrefix(dataBase.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataPath))
        XCTAssertTrue(try XCTUnwrap(arguments.string("stdin")).contains("Private prompt"))
        let redacted = invocation.call.redactedForTranscript().argumentsJSON
        XCTAssertFalse(redacted.contains("Private prompt"))
        XCTAssertFalse(redacted.contains(pluginRoot.path))
        XCTAssertTrue(redacted.contains(ToolCall.redactedStandardInputValue))
        XCTAssertTrue(redacted.contains(ToolCall.redactedEnvironmentValue))
    }

    func testPluginInvocationFailsClosedWithoutPrivateDataStorage() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo")
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let hook = ProjectRunHook(
            id: "plugin_hook:demo.stop.0.0",
            timing: .afterAgentRun,
            title: "Demo",
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#Stop/0/0",
            command: "touch must-not-run",
            pluginID: "plugin:demo",
            pluginRootRelativePath: ".quillcode/plugins/demo"
        )

        XCTAssertThrowsError(try ProjectRunHookInvocationBuilder.build(
            hook: hook,
            thread: ChatThread(),
            prompt: "Continue",
            workspaceRoot: root,
            pluginDataBaseDirectory: nil
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Private plugin data storage is unavailable.")
        }
    }
}
