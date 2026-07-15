import Foundation
import XCTest
@testable import QuillCodeTools

final class CodexPluginPackageDetailLoaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-plugin-detail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    func testLoadsDefaultComponentsAndFiltersSkillsByProduct() throws {
        try write(#"{"name":"demo-plugin"}"#, to: ".codex-plugin/plugin.json")
        try writeSkill(
            name: "thread-summarizer",
            description: "Summarize email threads",
            metadata: """
            interface:
              display_name: Thread Summarizer
              short_description: Condense long threads.
              brand_color: "#3B82F6"
            policy:
              products:
                - CODEX
            """
        )
        try writeSkill(
            name: "chatgpt-only",
            description: "Must remain hidden",
            metadata: """
            policy:
              products:
                - CHATGPT
            """
        )
        try write(
            #"{"apps":{"gmail":{"id":"gmail","category":"Communication"}}}"#,
            to: ".app.json"
        )
        try write(
            #"{"mcpServers":{"demo":{"command":"demo-server"},"invalid":{}}}"#,
            to: ".mcp.json"
        )
        try write(
            #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command"}]}],"PreToolUse":[{"hooks":[{"type":"command"},{"type":"command"}]}]}}"#,
            to: "hooks/hooks.json"
        )

        let detail = try XCTUnwrap(CodexPluginPackageDetailLoader.load(
            at: root,
            pluginIdentifier: "demo-plugin@codex-curated"
        ))

        XCTAssertEqual(detail.skills.map(\.name), ["thread-summarizer"])
        XCTAssertEqual(detail.skills.first?.description, "Summarize email threads")
        XCTAssertEqual(detail.skills.first?.interface?.displayName, "Thread Summarizer")
        XCTAssertEqual(detail.skills.first?.productRestrictions, ["CODEX"])
        XCTAssertEqual(detail.hooks, [
            CodexPluginHookDeclaration(
                key: "demo-plugin@codex-curated:hooks/hooks.json:pre_tool_use:0:0",
                event: .preToolUse
            ),
            CodexPluginHookDeclaration(
                key: "demo-plugin@codex-curated:hooks/hooks.json:pre_tool_use:0:1",
                event: .preToolUse
            ),
            CodexPluginHookDeclaration(
                key: "demo-plugin@codex-curated:hooks/hooks.json:session_start:0:0",
                event: .sessionStart
            )
        ])
        XCTAssertEqual(detail.apps, [
            CodexPluginAppDeclaration(id: "gmail", name: "gmail", category: "Communication")
        ])
        XCTAssertEqual(detail.mcpServerNames, ["demo"])
    }

    func testLoadsExplicitPathsAndInlineComponents() throws {
        try write(
            #"{"name":"demo","skills":"./components/skills","apps":"./config/apps.json","mcpServers":{"inline":{"url":"https://example.com/mcp"}},"hooks":{"hooks":{"Stop":[{"hooks":[{"type":"prompt"}]}]}}}"#,
            to: ".codex-plugin/plugin.json"
        )
        try writeSkill(
            rootPath: "components/skills",
            name: "review",
            description: "Review changes"
        )
        try write(
            #"{"apps":{"calendar":{"id":"calendar"}}}"#,
            to: "config/apps.json"
        )

        let detail = try XCTUnwrap(CodexPluginPackageDetailLoader.load(
            at: root,
            pluginIdentifier: "demo@local"
        ))

        XCTAssertEqual(detail.skills.map(\.name), ["review"])
        XCTAssertEqual(detail.hooks, [
            CodexPluginHookDeclaration(
                key: "demo@local:plugin.json#hooks[0]:stop:0:0",
                event: .stop
            )
        ])
        XCTAssertEqual(detail.apps.map(\.id), ["calendar"])
        XCTAssertEqual(detail.mcpServerNames, ["inline"])
    }

    func testExplicitInvalidSkillPathDoesNotFallBackToDefaultSkills() throws {
        try write(
            #"{"name":"demo","skills":"../outside"}"#,
            to: ".codex-plugin/plugin.json"
        )
        try writeSkill(name: "unexpected", description: "Must not be loaded")

        let detail = try XCTUnwrap(CodexPluginPackageDetailLoader.load(
            at: root,
            pluginIdentifier: "demo@local"
        ))

        XCTAssertTrue(detail.skills.isEmpty)
    }

    func testRejectsSymlinkedRootsAndNestedComponentEscapes() throws {
        try write(#"{"name":"demo","apps":"./linked/apps.json"}"#, to: ".codex-plugin/plugin.json")
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
        try #"{"apps":{"escaped":{"id":"escaped"}}}"#.write(
            to: outside.appendingPathComponent("apps.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"),
            withDestinationURL: outside
        )

        let detail = try XCTUnwrap(CodexPluginPackageDetailLoader.load(
            at: root,
            pluginIdentifier: "demo@local"
        ))
        XCTAssertTrue(detail.apps.isEmpty)

        let linkedRoot = root.deletingLastPathComponent()
            .appendingPathComponent("linked-root-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: linkedRoot) }
        XCTAssertNil(CodexPluginPackageDetailLoader.load(
            at: linkedRoot,
            pluginIdentifier: "demo@local"
        ))
    }

    func testSkipsOversizedComponentFilesAndRejectsInvalidManifest() throws {
        try write(#"{"name":"demo"}"#, to: ".codex-plugin/plugin.json")
        try write(
            #"{"apps":{"oversized":{"id":"oversized"}}}"#,
            to: ".app.json"
        )

        let detail = try XCTUnwrap(CodexPluginPackageDetailLoader.load(
            at: root,
            pluginIdentifier: "demo@local",
            maximumComponentFileBytes: 16
        ))
        XCTAssertTrue(detail.apps.isEmpty)

        try write("{not json", to: ".codex-plugin/plugin.json")
        XCTAssertNil(CodexPluginPackageDetailLoader.load(
            at: root,
            pluginIdentifier: "demo@local"
        ))
    }

    private func writeSkill(
        rootPath: String = "skills",
        name: String,
        description: String,
        metadata: String? = nil
    ) throws {
        try write(
            """
            ---
            name: \(name)
            description: \(description)
            ---

            # \(name)
            """,
            to: "\(rootPath)/\(name)/SKILL.md"
        )
        if let metadata {
            try write(metadata, to: "\(rootPath)/\(name)/agents/openai.yaml")
        }
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
}
