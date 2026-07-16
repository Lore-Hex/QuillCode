import Foundation
@testable import QuillCodePersistence
import XCTest

final class MemoryDirectoryResetterTests: XCTestCase {
    func testClearRemovesNestedAndHiddenContentWhilePreservingRoot() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("memories", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("memory.md"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden-memory"))

        try MemoryDirectoryResetter.clear(root)

        XCTAssertTrue(try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
            []
        )
        XCTAssertEqual(try permissions(at: root), 0o700)
    }

    func testClearRemovesChildSymlinkWithoutFollowingIt() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("memories", isDirectory: true)
        let external = parent.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sentinel = external.appendingPathComponent("preserve.md")
        try Data("preserve".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("external-link"),
            withDestinationURL: external
        )

        try MemoryDirectoryResetter.clear(root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
            []
        )
    }

    func testClearCreatesMissingPrivateDirectoryAndIsIdempotent() throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("memories", isDirectory: true)

        try MemoryDirectoryResetter.clear(root)
        try MemoryDirectoryResetter.clear(root)

        XCTAssertTrue(try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        XCTAssertEqual(try permissions(at: root), 0o700)
    }

    func testClearRejectsSymlinkAndRegularFileRoots() throws {
        let parent = try temporaryDirectory()
        let external = parent.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sentinel = external.appendingPathComponent("preserve.md")
        try Data("preserve".utf8).write(to: sentinel)
        let symlink = parent.appendingPathComponent("memory-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: external)

        XCTAssertThrowsError(try MemoryDirectoryResetter.clear(symlink)) { error in
            XCTAssertEqual(error as? MemoryDirectoryResetError, .unsafeRoot)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))

        let file = parent.appendingPathComponent("memory-file")
        try Data("not a directory".utf8).write(to: file)
        XCTAssertThrowsError(try MemoryDirectoryResetter.clear(file)) { error in
            XCTAssertEqual(error as? MemoryDirectoryResetError, .unsafeRoot)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-memory-reset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func permissions(at directory: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        return try XCTUnwrap((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }
}
