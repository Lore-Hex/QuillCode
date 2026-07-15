import Foundation
@testable import QuillCodeCLI
import XCTest

final class CLIRepositoryGuardTests: XCTestCase {
    func testAcceptsGitDirectoryAndWorktreeFileFromNestedDirectory() throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        XCTAssertEqual(CLIRepositoryGuard().repositoryRoot(containing: nested)?.path, root.path)

        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        try "gitdir: elsewhere".write(to: root.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try CLIRepositoryGuard().validate(nested))
    }

    func testRejectsNonRepositoryAndMissingDirectory() throws {
        let root = try temporaryDirectory()
        XCTAssertThrowsError(try CLIRepositoryGuard().validate(root))
        XCTAssertThrowsError(try CLIRepositoryGuard().validate(root.appendingPathComponent("missing")))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-cli-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
