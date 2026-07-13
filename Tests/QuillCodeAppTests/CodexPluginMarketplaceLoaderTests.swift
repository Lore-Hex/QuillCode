import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class CodexPluginMarketplaceLoaderTests: XCTestCase {
    func testLoadsBoundedLocalEntriesAndRejectsUnsupportedSources() throws {
        let root = try makeQuillCodeTestDirectory()
        try makePackage(named: "alpha", in: root, displayName: "Alpha Tools")
        try makePackage(named: "beta", in: root)
        try makePackage(named: "blocked", in: root)
        try makePackage(named: "actual-name", in: root, directoryName: "mismatch")
        try writeCatalog(
            """
            {
              "name": "repo-tools",
              "plugins": [
                {"name":"remote","source":{"source":"git","url":"https://example.com/plugin.git"}},
                {"name":"alpha","source":{"source":"local","path":"./catalog/alpha"}},
                {"name":"blocked","source":"./catalog/blocked","policy":{"installation":"NOT_AVAILABLE"}},
                {"name":"mismatch","source":"./catalog/mismatch"},
                {"name":"beta","source":"./catalog/beta"}
              ]
            }
            """,
            at: ".agents/plugins/marketplace.json",
            root: root
        )

        let manifests = CodexPluginMarketplaceLoader.load(
            from: root,
            installedManifests: [],
            maxPlugins: 2
        )

        XCTAssertEqual(manifests.map(\.id), ["plugin:alpha", "plugin:beta"])
        XCTAssertEqual(manifests.map(\.name), ["Alpha Tools", "Beta"])
        XCTAssertEqual(manifests.map(\.localInstallSourceRelativePath), [
            "./catalog/alpha",
            "./catalog/beta"
        ])
        XCTAssertTrue(manifests.allSatisfy { $0.installCommand == nil && $0.packageRootRelativePath == nil })
        XCTAssertEqual(manifests.map { ProjectExtensionManifestSurface(manifest: $0).statusLabel }, [
            "Available",
            "Available"
        ])
    }

    func testModernCatalogWinsAndInstalledPluginIsFiltered() throws {
        let root = try makeQuillCodeTestDirectory()
        try makePackage(named: "alpha", in: root, displayName: "Modern Alpha")
        try makePackage(named: "beta", in: root)
        try writeCatalog(
            #"{"name":"modern","plugins":[{"name":"alpha","source":"./catalog/alpha"},{"name":"beta","source":"./catalog/beta"}]}"#,
            at: ".agents/plugins/marketplace.json",
            root: root
        )
        try writeCatalog(
            #"{"name":"legacy","plugins":[{"name":"alpha","source":"./catalog/alpha"}]}"#,
            at: ".claude-plugin/marketplace.json",
            root: root
        )

        let manifests = CodexPluginMarketplaceLoader.load(
            from: root,
            installedManifests: [ProjectExtensionManifest(
                id: "plugin:beta",
                kind: .plugin,
                name: "Beta",
                relativePath: ".quillcode/plugins/beta/.codex-plugin/plugin.json"
            )]
        )

        XCTAssertEqual(manifests.map(\.id), ["plugin:alpha"])
        XCTAssertEqual(manifests.first?.relativePath, ".agents/plugins/marketplace.json#alpha")
    }

    func testRejectsUnsafeCatalogAndSourcePaths() throws {
        let root = try makeQuillCodeTestDirectory()
        let outside = try makeQuillCodeTestDirectory()
        try makePackage(named: "outside", in: outside)
        let agents = root.appendingPathComponent(".agents/plugins")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let outsideCatalog = outside.appendingPathComponent("marketplace.json")
        try #"{"name":"outside","plugins":[{"name":"outside","source":"./catalog/outside"}]}"#.write(
            to: outsideCatalog,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: agents.appendingPathComponent("marketplace.json"),
            withDestinationURL: outsideCatalog
        )

        XCTAssertTrue(CodexPluginMarketplaceLoader.load(
            from: root,
            installedManifests: []
        ).isEmpty)

        try FileManager.default.removeItem(at: agents.appendingPathComponent("marketplace.json"))
        try writeCatalog(
            #"{"name":"unsafe","plugins":[{"name":"outside","source":"../outside"},{"name":"absolute","source":"/tmp/plugin"}]}"#,
            at: ".agents/plugins/marketplace.json",
            root: root
        )
        XCTAssertTrue(CodexPluginMarketplaceLoader.load(
            from: root,
            installedManifests: []
        ).isEmpty)
    }

    func testMetadataTransitionsFromAvailableToInstalledAfterTypedInstall() throws {
        let root = try makeQuillCodeTestDirectory()
        try makePackage(named: "alpha", in: root, displayName: "Alpha Tools")
        try writeCatalog(
            #"{"name":"repo-tools","plugins":[{"name":"alpha","source":"./catalog/alpha"}]}"#,
            at: ".agents/plugins/marketplace.json",
            root: root
        )

        let available = try XCTUnwrap(
            WorkspaceProjectMetadataLoader.loadLocal(from: root).extensionManifests.first {
                $0.id == "plugin:alpha"
            }
        )
        XCTAssertNotNil(available.localInstallSourceRelativePath)
        let call = try XCTUnwrap(WorkspaceExtensionToolCallPlanner.install(available))
        XCTAssertTrue(ToolRouter(workspaceRoot: root).execute(call).ok)

        let matches = WorkspaceProjectMetadataLoader.loadLocal(from: root).extensionManifests.filter {
            $0.id == "plugin:alpha"
        }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.packageRootRelativePath, ".quillcode/plugins/alpha")
        XCTAssertNil(matches.first?.localInstallSourceRelativePath)
        XCTAssertEqual(ProjectExtensionManifestSurface(manifest: try XCTUnwrap(matches.first)).statusLabel, "Discovered")
    }

    private func makePackage(
        named name: String,
        in root: URL,
        displayName: String? = nil,
        directoryName: String? = nil
    ) throws {
        let package = root.appendingPathComponent("catalog/\(directoryName ?? name)")
        let manifest = package.appendingPathComponent(".codex-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let interface = displayName.map { #", "interface":{"displayName":"\#($0)"}"# } ?? ""
        try #"{"name":"\#(name)","version":"1.0.0"\#(interface)}"#.write(
            to: manifest,
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeCatalog(_ content: String, at relativePath: String, root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
