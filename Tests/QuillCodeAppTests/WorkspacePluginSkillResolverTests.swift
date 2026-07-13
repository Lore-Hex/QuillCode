import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspacePluginSkillResolverTests: XCTestCase {
    func testDirectProjectSkillShadowsPluginAndPluginShadowsGlobalSkill() throws {
        let root = try makeQuillCodeTestDirectory()
        let home = try makeQuillCodeTestDirectory()
        let direct = root.appendingPathComponent(".quillcode/skills/review")
        let plugin = root.appendingPathComponent(".quillcode/plugins/acme/skills/review")
        let pluginOnly = root.appendingPathComponent(".quillcode/plugins/acme/skills/search")
        let global = home.appendingPathComponent(".quillcode/skills/review")
        for directory in [direct, plugin, pluginOnly, global] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try directory.path.write(
                to: directory.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        let manifest = ProjectExtensionManifest(
            id: "plugin:acme",
            kind: .plugin,
            name: "Acme",
            relativePath: ".quillcode/plugins/acme/.codex-plugin/plugin.json",
            skillDirectoryRelativePaths: [".quillcode/plugins/acme/skills"]
        )

        let resolver = WorkspacePluginSkillResolver.make(
            workspaceRoot: root,
            manifests: [manifest],
            homeDirectory: home
        )

        XCTAssertEqual(
            try resolver.resolve(name: "review").baseDirectory.standardizedFileURL.path,
            direct.standardizedFileURL.path
        )
        XCTAssertEqual(
            try resolver.resolve(name: "search").baseDirectory.standardizedFileURL.path,
            pluginOnly.standardizedFileURL.path
        )
        XCTAssertEqual(resolver.availableSkillNames(), ["review", "search"])
    }

    func testDisabledPluginAndEscapingSkillRootAreIgnored() throws {
        let root = try makeQuillCodeTestDirectory()
        let home = try makeQuillCodeTestDirectory()
        let outside = try makeQuillCodeTestDirectory()
        let disabled = ProjectExtensionManifest(
            id: "plugin:disabled",
            kind: .plugin,
            name: "Disabled",
            relativePath: ".quillcode/plugins/disabled/.codex-plugin/plugin.json",
            isEnabled: false,
            skillDirectoryRelativePaths: [outside.path]
        )

        let resolver = WorkspacePluginSkillResolver.make(
            workspaceRoot: root,
            manifests: [disabled],
            homeDirectory: home
        )

        XCTAssertTrue(resolver.availableSkillNames().isEmpty)
        XCTAssertEqual(resolver.roots.count, 2)
    }
}
