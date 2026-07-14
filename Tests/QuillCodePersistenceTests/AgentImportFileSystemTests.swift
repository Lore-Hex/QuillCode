import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class AgentImportFileSystemTests: PersistenceTestCase {
    func testSourceSymlinkEscapeIsRejected() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: outside)
        let link = root.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertNil(AgentImportFileSystem.regularFile(link, inside: root))
        XCTAssertNil(AgentImportFileSystem.readData(link, inside: root))
    }

    func testDirectoryCopyExcludesCredentialsAndDependencyTrees() throws {
        let sourceRoot = try makeTempDirectory()
        let source = sourceRoot.appendingPathComponent("plugin")
        let destinationRoot = try makeTempDirectory()
        let destination = destinationRoot.appendingPathComponent("copied")
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("node_modules/pkg"),
            withIntermediateDirectories: true
        )
        try Data("safe".utf8).write(to: source.appendingPathComponent("main.txt"))
        try Data("secret".utf8).write(to: source.appendingPathComponent(".env"))
        try Data("dependency".utf8).write(to: source.appendingPathComponent("node_modules/pkg/index.js"))

        let count = try AgentImportFileSystem.copyDirectory(
            source,
            sourceRoot: sourceRoot,
            to: destination,
            destinationRoot: destinationRoot
        )

        XCTAssertEqual(count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("main.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".env").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("node_modules").path))
    }

    func testWriteNewNeverOverwritesExistingData() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("existing.txt")
        try Data("original".utf8).write(to: file)

        XCTAssertThrowsError(
            try AgentImportFileSystem.writeNew(Data("replacement".utf8), to: file, inside: root)
        )
        XCTAssertEqual(try Data(contentsOf: file), Data("original".utf8))
    }
}
