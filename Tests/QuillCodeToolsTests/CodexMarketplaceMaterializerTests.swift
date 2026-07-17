import Foundation
@testable import QuillCodeTools
import XCTest

final class CodexMarketplaceMaterializerTests: XCTestCase {
    func testPreparesLocalMarketplaceWithoutCopyingIt() throws {
        let home = try temporaryDirectory(prefix: "home")
        let source = try temporaryDirectory(prefix: "source")
        try writeMarketplace(name: "team-tools", marker: "local", at: source)
        let materializer = CodexMarketplaceMaterializer(home: home, currentDirectory: source)

        let prepared = try materializer.prepare(source: source.path, refName: nil, sparsePaths: [])

        XCTAssertEqual(prepared.name, "team-tools")
        XCTAssertEqual(prepared.root, source.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(prepared.sourceType, .local)
        XCTAssertFalse(prepared.managed)
        let activation = try materializer.activate(prepared, replacingExisting: false)
        XCTAssertEqual(activation.installedRoot, prepared.root)
    }

    func testClonesActivatesAndRollsBackGitMarketplace() throws {
        let home = try temporaryDirectory(prefix: "home")
        let source = try temporaryDirectory(prefix: "git-source")
        try initializeGitMarketplace(name: "team-tools", marker: "v1", at: source)
        let firstRevision = try git(["rev-parse", "HEAD"], in: source)
        let materializer = CodexMarketplaceMaterializer(home: home, currentDirectory: source)
        let prepared = try materializer.prepare(
            source: source.path,
            refName: firstRevision,
            sparsePaths: []
        )
        XCTAssertEqual(prepared.sourceType, .git)
        XCTAssertEqual(prepared.revision, firstRevision)
        let first = try materializer.activate(prepared, replacingExisting: false)
        try materializer.finalize(first)
        XCTAssertEqual(
            try String(contentsOf: first.installedRoot.appendingPathComponent("marker.txt"), encoding: .utf8),
            "v1"
        )

        try "v2".write(
            to: source.appendingPathComponent("marker.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try git(["add", "marker.txt"], in: source)
        _ = try git(["commit", "-m", "v2"], in: source)
        let secondRevision = try git(["rev-parse", "HEAD"], in: source)
        let replacement = try materializer.prepare(
            source: source.path,
            refName: secondRevision,
            sparsePaths: []
        )
        let second = try materializer.activate(replacement, replacingExisting: true)
        XCTAssertEqual(
            try String(contentsOf: second.installedRoot.appendingPathComponent("marker.txt"), encoding: .utf8),
            "v2"
        )

        try materializer.rollback(second)
        XCTAssertEqual(
            try String(contentsOf: first.installedRoot.appendingPathComponent("marker.txt"), encoding: .utf8),
            "v1"
        )
    }

    func testRejectsInvalidSparsePathsAndCatalogSymlinks() throws {
        let home = try temporaryDirectory(prefix: "home")
        let source = try temporaryDirectory(prefix: "source")
        try writeMarketplace(name: "team-tools", marker: "local", at: source)
        let materializer = CodexMarketplaceMaterializer(home: home, currentDirectory: source)

        XCTAssertThrowsError(try materializer.prepare(
            source: source.path,
            refName: "HEAD",
            sparsePaths: ["../escape"]
        ))

        let linked = try temporaryDirectory(prefix: "linked")
        try FileManager.default.createDirectory(
            at: linked.appendingPathComponent(".agents/plugins", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent(".agents/plugins/marketplace.json"),
            withDestinationURL: source.appendingPathComponent(".agents/plugins/marketplace.json")
        )
        XCTAssertThrowsError(try materializer.prepare(
            source: linked.path,
            refName: nil,
            sparsePaths: []
        ))
    }

    private func initializeGitMarketplace(name: String, marker: String, at root: URL) throws {
        _ = try git(["init", "-b", "main"], in: root)
        _ = try git(["config", "user.email", "quillcode@example.test"], in: root)
        _ = try git(["config", "user.name", "QuillCode Tests"], in: root)
        try writeMarketplace(name: name, marker: marker, at: root)
        _ = try git(["add", "."], in: root)
        _ = try git(["commit", "-m", "initial"], in: root)
    }

    private func writeMarketplace(name: String, marker: String, at root: URL) throws {
        let catalog = root.appendingPathComponent(".agents/plugins/marketplace.json")
        let package = root.appendingPathComponent("plugins/review/.codex-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: catalog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: package.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"name":"\#(name)","plugins":[{"name":"review","source":"./plugins/review"}]}"#
            .write(to: catalog, atomically: true, encoding: .utf8)
        try #"{"name":"review","version":"1.0.0"}"#
            .write(to: package, atomically: true, encoding: .utf8)
        try marker.write(
            to: root.appendingPathComponent("marker.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let result = GitProcessRunner().runGit(arguments, cwd: directory, timeoutSeconds: 20)
        guard result.ok else {
            throw MaterializerTestError.git(result.stderr.isEmpty ? (result.error ?? "git failed") : result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-marketplace-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private enum MaterializerTestError: Error {
    case git(String)
}
