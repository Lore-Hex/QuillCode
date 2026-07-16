import Foundation
import XCTest
@testable import QuillCodeHooks

final class CodexPluginHookConfigurationLoaderTests: XCTestCase {
    func testLoadsPathBackedPluginHookWithStableMetadata() throws {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent(".quillcode/plugins/sample", isDirectory: true)
        try write(
            #"{"name":"sample","interface":{"displayName":"Sample Plugin"},"hooks":"./hooks/custom.json"}"#,
            to: ".codex-plugin/plugin.json",
            in: package
        )
        try write(
            #"{"hooks":{"PreToolUse":[{"matcher":"shell.run","hooks":[{"type":"command","command":"printf plugin","timeout":12}]}]}}"#,
            to: "hooks/custom.json",
            in: package
        )

        let discovery = CodexPluginHookConfigurationLoader.loadPackage(
            at: package,
            scopeRoot: root
        )

        let definition = try XCTUnwrap(discovery.definitions.first)
        XCTAssertTrue(discovery.warnings.isEmpty)
        XCTAssertEqual(definition.key, "sample:hooks/custom.json:pre_tool_use:0:0")
        XCTAssertEqual(definition.source, .plugin)
        XCTAssertEqual(definition.pluginID, "sample")
        XCTAssertEqual(definition.hook.pluginName, "Sample Plugin")
        XCTAssertEqual(definition.hook.command, "printf plugin")
        XCTAssertEqual(definition.hook.timeoutSeconds, 12)
        XCTAssertEqual(definition.sourcePath.path, package.appendingPathComponent("hooks/custom.json").path)
    }

    func testLoadsInlinePluginHooksFromManifest() throws {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent("plugins/inline", isDirectory: true)
        try write(
            """
            {
              "name": "inline",
              "hooks": {
                "hooks": {
                  "Stop": [{"hooks": [{"type": "command", "command": "printf inline"}]}]
                }
              }
            }
            """,
            to: ".claude-plugin/plugin.json",
            in: package
        )

        let discovery = CodexPluginHookConfigurationLoader.loadPackage(
            at: package,
            scopeRoot: root
        )

        XCTAssertEqual(discovery.definitions.map(\.key), ["inline:plugin.json#hooks[0]:stop:0:0"])
        XCTAssertEqual(discovery.definitions.first?.hook.command, "printf inline")
        XCTAssertEqual(
            discovery.definitions.first?.sourcePath.path,
            package.appendingPathComponent(".claude-plugin/plugin.json").path
        )
    }

    func testMalformedAndUnsupportedPluginHooksProduceWarningsWithoutExecution() throws {
        let root = try temporaryDirectory()
        let packages = root.appendingPathComponent("plugins", isDirectory: true)
        let malformed = packages.appendingPathComponent("malformed", isDirectory: true)
        try write(
            #"{"name":"malformed","hooks":"hooks/hooks.json"}"#,
            to: ".codex-plugin/plugin.json",
            in: malformed
        )
        try write("not json", to: "hooks/hooks.json", in: malformed)

        let unsupported = packages.appendingPathComponent("unsupported", isDirectory: true)
        try write(
            #"{"name":"unsupported","hooks":"hooks/hooks.json"}"#,
            to: ".codex-plugin/plugin.json",
            in: unsupported
        )
        try write(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"prompt","prompt":"never run"}]}]}}"#,
            to: "hooks/hooks.json",
            in: unsupported
        )

        let discovery = CodexPluginHookConfigurationLoader.discover(
            packageDirectories: [packages],
            scopeRoot: root
        )

        XCTAssertEqual(discovery.definitions.count, 1)
        XCTAssertEqual(discovery.definitions.first?.hook.supportStatus, .unsupportedHandler)
        XCTAssertTrue(discovery.warnings.contains { $0.contains("failed to parse plugin hooks") })
        XCTAssertTrue(discovery.warnings.contains { $0.contains("unsupported_handler") })
        XCTAssertTrue(HookCatalogResolver.resolve(discovery.definitions).isEmpty)
    }

    func testRejectsHookFileSymlinkOutsidePackage() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let package = root.appendingPathComponent("plugins/sample", isDirectory: true)
        try write(
            #"{"name":"sample","hooks":"hooks/hooks.json"}"#,
            to: ".codex-plugin/plugin.json",
            in: package
        )
        let outsideFile = outside.appendingPathComponent("hooks.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf escaped"}]}]}}"#
            .write(to: outsideFile, atomically: true, encoding: .utf8)
        let link = package.appendingPathComponent("hooks/hooks.json")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

        let discovery = CodexPluginHookConfigurationLoader.loadPackage(
            at: package,
            scopeRoot: root
        )

        XCTAssertTrue(discovery.definitions.isEmpty)
        XCTAssertTrue(discovery.warnings.contains { $0.contains("missing or unsafe") })
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPluginHookLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func write(_ value: String, to relativePath: String, in root: URL) throws {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try value.write(to: destination, atomically: true, encoding: .utf8)
    }
}
