import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class LocalPluginInstallToolExecutorTests: XCTestCase {
    func testInstallsValidatedPackageAtomically() throws {
        let root = try makeTempDirectory()
        let source = try makePackage(named: "review-kit", in: root)
        try "# Review\n".write(
            to: source.appendingPathComponent("skills/review/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/sh\ntouch .quillcode/plugin-lifecycle-ran\n".write(
            to: source.appendingPathComponent("install.sh"),
            atomically: true,
            encoding: .utf8
        )

        let result = LocalPluginInstallToolExecutor(workspaceRoot: root).install(
            sourceRelativePath: "./catalog/review-kit",
            expectedPluginName: "review-kit"
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        let destination = root.appendingPathComponent(".quillcode/plugins/review-kit")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(".codex-plugin/plugin.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("skills/review/SKILL.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("install.sh").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".quillcode/plugin-lifecycle-ran").path
        ))
        XCTAssertEqual(result.artifacts, [destination.path])
        let stagingEntries = try FileManager.default.contentsOfDirectory(
            at: destination.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".review-kit.install-") }
        XCTAssertTrue(stagingEntries.isEmpty)
    }

    func testRejectsStaleIdentityAndExistingDestination() throws {
        let root = try makeTempDirectory()
        _ = try makePackage(named: "different", in: root, directoryName: "review-kit")
        let executor = LocalPluginInstallToolExecutor(workspaceRoot: root)

        let stale = executor.install(
            sourceRelativePath: "./catalog/review-kit",
            expectedPluginName: "review-kit"
        )
        XCTAssertFalse(stale.ok)
        XCTAssertTrue(stale.error?.contains("no longer matches") == true)

        _ = try makePackage(named: "review-kit", in: root, directoryName: "valid")
        let destination = root.appendingPathComponent(".quillcode/plugins/review-kit")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let collision = executor.install(
            sourceRelativePath: "./catalog/valid",
            expectedPluginName: "review-kit"
        )
        XCTAssertFalse(collision.ok)
        XCTAssertTrue(collision.error?.contains("already installed") == true)
    }

    func testRejectsTraversalAndSymbolicEntries() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        let package = try makePackage(named: "review-kit", in: root)
        let outsideFile = outside.appendingPathComponent("secret.txt")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent("secret.txt"),
            withDestinationURL: outsideFile
        )
        let executor = LocalPluginInstallToolExecutor(workspaceRoot: root)

        let traversal = executor.install(
            sourceRelativePath: "./../outside",
            expectedPluginName: "review-kit"
        )
        XCTAssertFalse(traversal.ok)
        XCTAssertTrue(traversal.error?.contains("inside the project workspace") == true)

        let symlink = executor.install(
            sourceRelativePath: "./catalog/review-kit",
            expectedPluginName: "review-kit"
        )
        XCTAssertFalse(symlink.ok)
        XCTAssertTrue(symlink.error?.contains("symbolic entry") == true)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".quillcode/plugins/review-kit").path
        ))
    }

    func testRouterDispatchesTypedInstallWithoutAdvertisingItToTheModel() throws {
        let root = try makeTempDirectory()
        _ = try makePackage(named: "review-kit", in: root)
        let call = ToolCall(
            name: ToolDefinition.localPluginInstall.name,
            argumentsJSON: ToolArguments.json([
                "source": "./catalog/review-kit",
                "pluginName": "review-kit"
            ])
        )

        let result = ToolRouter(workspaceRoot: root).execute(call)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertFalse(ToolRouter.definitions.map(\.name).contains(ToolDefinition.localPluginInstall.name))
    }

    @discardableResult
    private func makePackage(
        named name: String,
        in root: URL,
        directoryName: String? = nil
    ) throws -> URL {
        let package = root.appendingPathComponent("catalog/\(directoryName ?? name)")
        let manifest = package.appendingPathComponent(".codex-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("skills/review"),
            withIntermediateDirectories: true
        )
        try #"{"name":"\#(name)","version":"1.0.0","skills":"./skills"}"#.write(
            to: manifest,
            atomically: true,
            encoding: .utf8
        )
        return package
    }
}
