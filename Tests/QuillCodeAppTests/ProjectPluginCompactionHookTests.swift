import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectPluginCompactionHookTests: XCTestCase {
    func testInvocationUsesCanonicalPayloadWithoutPermissionMode() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let thread = ChatThread(title: "Compaction", mode: .auto, model: "trustedrouter/fast")
        let invocation = try ProjectPluginCompactionHookInvocationBuilder.build(
            hook: hook(event: .preCompact, matcher: "manual", command: "true"),
            event: .preCompact,
            trigger: .manual,
            thread: thread,
            workspaceRoot: root,
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true)
        )
        let arguments = try XCTUnwrap(jsonObject(invocation.call.argumentsJSON))
        let payload = try XCTUnwrap(jsonObject(try XCTUnwrap(arguments["stdin"] as? String)))

        XCTAssertEqual(payload["hook_event_name"] as? String, "PreCompact")
        XCTAssertEqual(payload["trigger"] as? String, "manual")
        XCTAssertEqual(payload["model"] as? String, "trustedrouter/fast")
        XCTAssertNotNil(payload["session_id"])
        XCTAssertNotNil(payload["turn_id"])
        XCTAssertTrue(payload["transcript_path"] is NSNull)
        XCTAssertNil(payload["permission_mode"])
        XCTAssertNil(payload["tool_name"])
    }

    func testParserSupportsCommonFieldsAndBoundsMessages() throws {
        let oversized = String(repeating: "x", count: 5_000) + "\0secret"
        let data = try JSONSerialization.data(withJSONObject: [
            "continue": false,
            "stopReason": oversized,
            "systemMessage": "notice",
            "suppressOutput": true
        ], options: [.sortedKeys])
        let output = try ProjectPluginCompactionHookOutputParser.parse(
            ToolResult(ok: true, stdout: String(decoding: data, as: UTF8.self))
        )

        XCTAssertFalse(output.continues)
        XCTAssertEqual(output.systemMessage, "notice")
        XCTAssertEqual(
            output.stopReason?.count,
            ProjectPluginCompactionHookOutputParser.maximumMessageCharacters + 3
        )
        XCTAssertFalse(output.stopReason?.contains("\0") == true)
        XCTAssertFalse(output.stopReason?.contains("secret") == true)
    }

    func testMalformedOrUnsupportedOutputFailsParsing() {
        XCTAssertThrowsError(try ProjectPluginCompactionHookOutputParser.parse(
            ToolResult(ok: true, stdout: "not json")
        ))
        XCTAssertThrowsError(try ProjectPluginCompactionHookOutputParser.parse(
            ToolResult(ok: true, stdout: #"{"continue":"yes"}"#)
        ))
        XCTAssertThrowsError(try ProjectPluginCompactionHookOutputParser.parse(
            ToolResult(ok: true, stdout: #"{"hookSpecificOutput":{}}"#)
        ))
    }

    func testMatcherSeparatesManualAndAutoAndAnyStopWinsInConfigurationOrder() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let executor = ProjectPluginCompactionHookExecutor(
            hooks: [
                hook(
                    event: .preCompact,
                    matcher: "^manual$",
                    command: #"printf '%s' '{"systemMessage":"manual only"}'"#
                ),
                hook(
                    event: .preCompact,
                    matcher: "^(manual|auto)$",
                    command: #"printf '%s' '{"continue":false,"stopReason":"first stop"}'"#
                ),
                hook(
                    event: .preCompact,
                    matcher: "^auto$",
                    command: #"printf '%s' '{"continue":false,"stopReason":"auto stop"}'"#
                )
            ],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let manual = await executor.run(
            event: .preCompact,
            trigger: .manual,
            thread: ChatThread(),
            workspaceRoot: root
        )
        XCTAssertFalse(manual.continues)
        XCTAssertEqual(manual.stopReason, "first stop")
        XCTAssertEqual(manual.notices, ["Hook warning from Demo Hooks: manual only"])

        let automatic = await executor.run(
            event: .preCompact,
            trigger: .auto,
            thread: ChatThread(),
            workspaceRoot: root
        )
        XCTAssertFalse(automatic.continues)
        XCTAssertEqual(automatic.stopReason, "first stop")
        XCTAssertTrue(automatic.notices.isEmpty)
    }

    func testCommandFailureAndMalformedOutputWarnButContinue() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let executor = ProjectPluginCompactionHookExecutor(
            hooks: [
                hook(event: .postCompact, matcher: "auto", command: "printf nope; exit 7"),
                hook(event: .postCompact, matcher: "auto", command: "printf malformed")
            ],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let output = await executor.run(
            event: .postCompact,
            trigger: .auto,
            thread: ChatThread(),
            workspaceRoot: root
        )

        XCTAssertTrue(output.continues)
        XCTAssertEqual(output.notices.count, 2)
        XCTAssertTrue(output.notices[0].contains("exit code 7"))
        XCTAssertTrue(output.notices[1].contains("valid JSON"))
        XCTAssertTrue(output.notices.allSatisfy { $0.hasSuffix("Compaction continued.") })
    }

    func testMatchingCommandsLaunchConcurrentlyAndFoldInConfigurationOrder() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let executor = ProjectPluginCompactionHookExecutor(
            hooks: [
                hook(
                    event: .preCompact,
                    matcher: "auto",
                    command: concurrentCommand(marker: "one", peer: "two", message: "first")
                ),
                hook(
                    event: .preCompact,
                    matcher: "auto",
                    command: concurrentCommand(marker: "two", peer: "one", message: "second")
                )
            ],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let output = await executor.run(
            event: .preCompact,
            trigger: .auto,
            thread: ChatThread(),
            workspaceRoot: root
        )

        XCTAssertTrue(output.continues)
        XCTAssertEqual(output.notices, [
            "Hook warning from Demo Hooks: first",
            "Hook warning from Demo Hooks: second"
        ])
    }

    private func hook(
        event: ProjectPluginCompactionHookEvent,
        matcher: String?,
        command: String
    ) -> ProjectPluginHook {
        ProjectPluginHook(
            id: "\(event.rawValue)-\(UUID().uuidString)",
            pluginID: "plugin:demo",
            pluginName: "Demo Hooks",
            event: event.rawValue,
            matcher: matcher,
            handlerType: "command",
            command: command,
            timeoutSeconds: 5,
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#\(event.rawValue)",
            pluginRootRelativePath: ".quillcode/plugins/demo",
            definitionHash: String(repeating: "a", count: 64),
            trustStatus: .trusted,
            supportStatus: .supported
        )
    }

    private func jsonObject(_ value: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
    }

    private func concurrentCommand(marker: String, peer: String, message: String) -> String {
        "touch \"$PLUGIN_DATA/\(marker)\"; "
            + "i=0; while [ ! -f \"$PLUGIN_DATA/\(peer)\" ] && [ $i -lt 100 ]; "
            + "do sleep 0.01; i=$((i+1)); done; "
            + "test -f \"$PLUGIN_DATA/\(peer)\"; "
            + "printf '%s' '{\"systemMessage\":\"\(message)\"}'"
    }
}
