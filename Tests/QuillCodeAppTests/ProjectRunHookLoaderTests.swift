import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class ProjectRunHookLoaderTests: XCTestCase {
    func testLegacyPersistedHookDefaultsToWorkspaceScope() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "legacy",
            "timing": "before_agent_run",
            "title": "Legacy",
            "relativePath": ".quillcode/hooks/before-agent-run/legacy.sh",
            "command": "true"
        ])

        let hook = try JSONDecoder().decode(ProjectRunHook.self, from: data)

        XCTAssertNil(hook.trustScope)
        XCTAssertEqual(hook.effectiveTrustScope, .workspace)
    }

    func testLoadsBeforeAndAfterHooksWithMetadata() throws {
        let root = try makeQuillCodeTestDirectory()
        let beforeDirectory = root.appendingPathComponent(".quillcode/hooks/before-agent-run")
        let afterDirectory = root.appendingPathComponent(".quillcode/hooks/after-agent-run")
        try FileManager.default.createDirectory(at: beforeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: afterDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("scripts"),
            withIntermediateDirectories: true
        )
        try "printf before".write(
            to: beforeDirectory.appendingPathComponent("z-before.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Prepare Context",
          "description": "Runs before every agent turn.",
          "order": 1,
          "working_directory": "scripts",
          "environment": { "QUILL_HOOK": "before" },
          "timeout_seconds": 30
        }
        """.write(
            to: beforeDirectory.appendingPathComponent("z-before.json"),
            atomically: true,
            encoding: .utf8
        )
        try "printf after".write(
            to: afterDirectory.appendingPathComponent("a-after.sh"),
            atomically: true,
            encoding: .utf8
        )

        let hooks = ProjectRunHookLoader.load(from: root)

        XCTAssertEqual(hooks.count, 2)
        XCTAssertEqual(hooks.map(\.timing), [.beforeAgentRun, .afterAgentRun])
        XCTAssertEqual(hooks.map(\.title), ["Prepare Context", "A After"])
        XCTAssertEqual(hooks[0].detail, "Runs before every agent turn.")
        XCTAssertEqual(hooks[0].relativePath, ".quillcode/hooks/before-agent-run/z-before.sh")
        XCTAssertEqual(hooks[0].command, #"cd 'scripts' && sh '../.quillcode/hooks/before-agent-run/z-before.sh'"#)
        XCTAssertEqual(hooks[0].environment, ["QUILL_HOOK": "before"])
        XCTAssertEqual(hooks[0].timeoutSeconds, 30)
    }

    func testRejectsUnsafeConfiguredDirectoryAndBoundsHooks() throws {
        let root = try makeQuillCodeTestDirectory()
        let hooksDirectory = root.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        try "printf one".write(
            to: hooksDirectory.appendingPathComponent("one.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "printf two".write(
            to: hooksDirectory.appendingPathComponent("two.sh"),
            atomically: true,
            encoding: .utf8
        )

        let hooks = ProjectRunHookLoader.load(
            from: root,
            beforeAgentRunDirectories: ["../escape", "hooks"],
            afterAgentRunDirectories: [],
            maxHooks: 1
        )

        XCTAssertEqual(hooks.map(\.relativePath), ["hooks/one.sh"])
    }
}
