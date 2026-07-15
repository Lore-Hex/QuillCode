import Foundation
import XCTest
@testable import QuillCodeTools

final class CodexPluginMarketplaceCatalogLoaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-plugin-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    func testLoadsBoundedLocalCatalogAndPackageInterface() throws {
        try write(
            #"""
            {
              "name": "team-tools",
              "interface": {"displayName": "Team Tools"},
              "plugins": [{
                "name": "review-kit",
                "source": {"source": "local", "path": "./catalog/review-kit"},
                "policy": {"installation": "AVAILABLE", "authentication": "ON_USE"},
                "category": "Engineering"
              }]
            }
            """#,
            to: ".agents/plugins/marketplace.json"
        )
        try write(
            #"""
            {
              "name": "review-kit",
              "version": "1.2.3",
              "description": "Review project changes.",
              "keywords": ["review", "git"],
              "interface": {
                "displayName": "Review Kit",
                "shortDescription": "Focused code review",
                "longDescription": "Review project changes with repository context.",
                "developerName": "Lore Hex",
                "category": "Productivity",
                "capabilities": ["Read", "Write"],
                "websiteURL": "https://example.com/review-kit",
                "privacyPolicyURL": "https://example.com/privacy",
                "termsOfServiceURL": "https://example.com/terms",
                "defaultPrompt": ["Review this change", "Find regressions"],
                "brandColor": "#31A8FF",
                "composerIcon": "./assets/composer.png",
                "logo": "./assets/logo.png",
                "logoDark": "./assets/logo-dark.png",
                "screenshots": ["./assets/one.png", "./assets/two.png"]
              }
            }
            """#,
            to: "catalog/review-kit/.codex-plugin/plugin.json"
        )

        let result = CodexPluginMarketplaceCatalogLoader.load(from: [root])

        XCTAssertTrue(result.errors.isEmpty)
        let marketplace = try XCTUnwrap(result.marketplaces.first)
        XCTAssertEqual(marketplace.name, "team-tools")
        XCTAssertEqual(marketplace.displayName, "Team Tools")
        XCTAssertEqual(marketplace.path, root.appendingPathComponent(".agents/plugins/marketplace.json"))
        let plugin = try XCTUnwrap(marketplace.plugins.first)
        XCTAssertEqual(plugin.name, "review-kit")
        XCTAssertEqual(plugin.installPolicy, .available)
        XCTAssertEqual(plugin.authPolicy, .onUse)
        XCTAssertEqual(plugin.category, "Engineering")
        XCTAssertEqual(plugin.source.localRelativePath, "./catalog/review-kit")
        XCTAssertEqual(plugin.source.localPath, root.appendingPathComponent("catalog/review-kit"))
        XCTAssertEqual(plugin.package?.version, "1.2.3")
        XCTAssertEqual(plugin.package?.keywords, ["review", "git"])
        XCTAssertEqual(plugin.package?.interface?.displayName, "Review Kit")
        XCTAssertEqual(plugin.package?.interface?.defaultPrompts, [
            "Review this change",
            "Find regressions"
        ])
        XCTAssertEqual(
            plugin.package?.interface?.composerIcon,
            root.appendingPathComponent("catalog/review-kit/assets/composer.png")
        )
        XCTAssertEqual(plugin.package?.interface?.screenshots.count, 2)
    }

    func testPreservesValidCatalogWhenAnotherCatalogIsInvalid() throws {
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try write(
            #"{"name":"valid","plugins":[{"name":"demo","source":"./demo"}]}"#,
            to: ".agents/plugins/marketplace.json"
        )
        try write("{not json", to: "other/.agents/plugins/marketplace.json")

        let result = CodexPluginMarketplaceCatalogLoader.load(from: [root, other])

        XCTAssertEqual(result.marketplaces.map(\.name), ["valid"])
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(
            result.errors[0].marketplacePath,
            other.appendingPathComponent(".agents/plugins/marketplace.json")
        )
        XCTAssertTrue(result.errors[0].message.contains("invalid marketplace file"))
    }

    func testAcceptsLegacyManifestAndStringPromptWhileRejectingEscapes() throws {
        try write(
            #"""
            {
              "name": "legacy",
              "plugins": [
                {"name": "remote", "source": {"source": "git", "url": "https://example.com/x"}},
                {"name": "escape", "source": "./../outside"},
                {"name": "valid", "source": "./plugins/valid"}
              ]
            }
            """#,
            to: ".claude-plugin/marketplace.json"
        )
        try write(
            #"{"name":"valid","interface":{"defaultPrompt":"Try this plugin"}}"#,
            to: "plugins/valid/.claude-plugin/plugin.json"
        )

        let result = CodexPluginMarketplaceCatalogLoader.load(
            from: [root],
            maximumPluginsPerMarketplace: 1
        )

        let plugin = try XCTUnwrap(result.marketplaces.first?.plugins.first)
        XCTAssertEqual(result.marketplaces.first?.plugins.count, 1)
        XCTAssertEqual(plugin.name, "valid")
        XCTAssertEqual(plugin.package?.interface?.defaultPrompts, ["Try this plugin"])
    }

    func testReportsSymlinkedAndOversizedCatalogsAsErrors() throws {
        let outside = root.appendingPathComponent("outside.json")
        try #"{"name":"outside","plugins":[]}"#.write(to: outside, atomically: true, encoding: .utf8)
        let symlink = root.appendingPathComponent(".agents/plugins/marketplace.json")
        try FileManager.default.createDirectory(
            at: symlink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        try write(
            String(repeating: "x", count: 64),
            to: ".claude-plugin/marketplace.json"
        )

        let result = CodexPluginMarketplaceCatalogLoader.load(
            from: [root],
            maximumCatalogBytes: 32
        )

        XCTAssertTrue(result.marketplaces.isEmpty)
        XCTAssertEqual(result.errors.count, 2)
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
