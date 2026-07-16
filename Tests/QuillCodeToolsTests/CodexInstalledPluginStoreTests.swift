import Foundation
@testable import QuillCodeTools
import XCTest

final class CodexInstalledPluginStoreTests: XCTestCase {
    func testInstallReplaceDiscoverSkillsAndIdempotentUninstall() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = try makePackage(named: "review-kit", version: "1.0.0", in: root)
        let skill = source.appendingPathComponent("skills/review/SKILL.md")
        try FileManager.default.createDirectory(
            at: skill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "---\nname: review\ndescription: Review changes\n---\n".write(
            to: skill,
            atomically: true,
            encoding: .utf8
        )
        let store = CodexInstalledPluginStore(home: home)

        let first = try store.install(
            source: source,
            pluginName: "review-kit",
            marketplaceName: "team-tools"
        )
        XCTAssertEqual(first.id, "review-kit@team-tools")
        XCTAssertEqual(first.metadata.version, "1.0.0")

        try writeManifest(named: "review-kit", version: "2.0.0", in: source)
        let replacement = try store.install(
            source: source,
            pluginName: "review-kit",
            marketplaceName: "team-tools"
        )
        XCTAssertEqual(replacement.metadata.version, "2.0.0")

        let packages = store.packages()
        XCTAssertEqual(packages.map(\.id), ["review-kit@team-tools"])
        XCTAssertEqual(packages.first?.metadata.version, "2.0.0")
        XCTAssertEqual(
            CodexInstalledPluginStore.marketplaceDirectories(in: home),
            [replacement.root.deletingLastPathComponent()]
        )

        let resolver = SkillResolver(roots: SkillResolver.roots(
            workspaceRoot: root,
            locations: .isolated(quillCodeHome: home)
        ))
        XCTAssertEqual(try resolver.resolve(name: "review").skillFile.lastPathComponent, "SKILL.md")

        try store.uninstall(pluginID: "review-kit@team-tools")
        try store.uninstall(pluginID: "review-kit@team-tools")
        XCTAssertTrue(store.packages().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement.root.path))
        XCTAssertThrowsError(try resolver.resolve(name: "review"))
    }

    func testDirectUserSkillPrecedesInstalledPluginSkillWithSameName() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = try makePackage(named: "review-kit", version: "1.0.0", in: root)
        let pluginSkill = source.appendingPathComponent("skills/review/SKILL.md")
        let userSkill = home.appendingPathComponent("skills/review/SKILL.md")
        for skill in [pluginSkill, userSkill] {
            try FileManager.default.createDirectory(
                at: skill.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try "---\nname: review\ndescription: Plugin review\n---\n".write(
            to: pluginSkill,
            atomically: true,
            encoding: .utf8
        )
        try "---\nname: review\ndescription: User review\n---\n".write(
            to: userSkill,
            atomically: true,
            encoding: .utf8
        )
        _ = try CodexInstalledPluginStore(home: home).install(
            source: source,
            pluginName: "review-kit",
            marketplaceName: "team-tools"
        )

        let resolver = SkillResolver(roots: SkillResolver.roots(
            workspaceRoot: root,
            locations: .isolated(quillCodeHome: home)
        ))

        XCTAssertEqual(try resolver.resolve(name: "review").skillFile.path, userSkill.path)
    }

    func testRejectsInvalidIdentityAndSymbolicPackageEntries() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let source = try makePackage(named: "review-kit", version: "1.0.0", in: root)
        let outside = root.appendingPathComponent("outside.txt")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("outside.txt"),
            withDestinationURL: outside
        )
        let store = CodexInstalledPluginStore(home: home)

        XCTAssertThrowsError(try store.install(
            source: source,
            pluginName: "review-kit",
            marketplaceName: "team-tools"
        )) { error in
            XCTAssertEqual(
                error as? PluginPackageInstallError,
                .unsupportedEntry("outside.txt")
            )
        }
        XCTAssertThrowsError(try store.uninstall(pluginID: "missing-marketplace"))
        XCTAssertThrowsError(try store.uninstall(pluginID: "bad/name@team-tools"))
        XCTAssertTrue(store.packages().isEmpty)
    }

    private func makePackage(named name: String, version: String, in root: URL) throws -> URL {
        let package = root.appendingPathComponent("catalog/\(name)", isDirectory: true)
        try writeManifest(named: name, version: version, in: package)
        return package
    }

    private func writeManifest(named name: String, version: String, in package: URL) throws {
        let manifest = package.appendingPathComponent(".codex-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"name":"\#(name)","version":"\#(version)"}"#.write(
            to: manifest,
            atomically: true,
            encoding: .utf8
        )
    }
}
