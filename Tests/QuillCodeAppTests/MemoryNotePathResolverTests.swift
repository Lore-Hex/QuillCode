import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class MemoryNotePathResolverTests: XCTestCase {
    func testProjectDirectoryRejectsTraversalAndAbsolutePaths() throws {
        let root = try makeQuillCodeTestDirectory()

        XCTAssertNil(MemoryNotePathResolver.projectMemoryDirectory(in: root, relativeDirectory: "../memories"))
        XCTAssertNil(MemoryNotePathResolver.projectMemoryDirectory(in: root, relativeDirectory: "/tmp/memories"))
        XCTAssertNil(MemoryNotePathResolver.projectMemoryDirectory(in: root, relativeDirectory: ""))

        let directory = try XCTUnwrap(
            MemoryNotePathResolver.projectMemoryDirectory(
                in: root,
                relativeDirectory: ".quillcode/memories"
            )
        )
        XCTAssertTrue(directory.path.hasPrefix(root.path + "/"))
    }

    func testGlobalFileURLRejectsNestedAndWrongScopePaths() throws {
        let root = try makeQuillCodeTestDirectory()
        let valid = memoryNote(scope: .global, relativePath: "memories/preference.md")
        let nested = memoryNote(scope: .global, relativePath: "memories/nested/preference.md")
        let traversal = memoryNote(scope: .global, relativePath: "memories/../preference.md")
        let wrongScope = memoryNote(scope: .project, relativePath: "memories/preference.md")

        XCTAssertEqual(
            MemoryNotePathResolver.globalMemoryFileURL(for: valid, in: root)?.path,
            root.appendingPathComponent("preference.md").path
        )
        XCTAssertNil(MemoryNotePathResolver.globalMemoryFileURL(for: nested, in: root))
        XCTAssertNil(MemoryNotePathResolver.globalMemoryFileURL(for: traversal, in: root))
        XCTAssertNil(MemoryNotePathResolver.globalMemoryFileURL(for: wrongScope, in: root))
    }

    func testProjectFileURLRejectsNestedWrongPrefixAndWrongScopePaths() throws {
        let root = try makeQuillCodeTestDirectory()
        let relativeDirectory = ".quillcode/memories"
        let directory = try XCTUnwrap(
            MemoryNotePathResolver.projectMemoryDirectory(
                in: root,
                relativeDirectory: relativeDirectory
            )
        )
        let valid = memoryNote(scope: .project, relativePath: ".quillcode/memories/project.md")
        let nested = memoryNote(scope: .project, relativePath: ".quillcode/memories/nested/project.md")
        let wrongPrefix = memoryNote(scope: .project, relativePath: ".quillcode/other/project.md")
        let wrongScope = memoryNote(scope: .global, relativePath: ".quillcode/memories/project.md")

        XCTAssertEqual(
            MemoryNotePathResolver.projectMemoryFileURL(
                for: valid,
                root: root,
                directory: directory,
                relativeDirectory: relativeDirectory
            )?.path,
            directory.appendingPathComponent("project.md").path
        )
        XCTAssertNil(
            MemoryNotePathResolver.projectMemoryFileURL(
                for: nested,
                root: root,
                directory: directory,
                relativeDirectory: relativeDirectory
            )
        )
        XCTAssertNil(
            MemoryNotePathResolver.projectMemoryFileURL(
                for: wrongPrefix,
                root: root,
                directory: directory,
                relativeDirectory: relativeDirectory
            )
        )
        XCTAssertNil(
            MemoryNotePathResolver.projectMemoryFileURL(
                for: wrongScope,
                root: root,
                directory: directory,
                relativeDirectory: relativeDirectory
            )
        )
    }

    private func memoryNote(scope: MemoryScope, relativePath: String) -> MemoryNote {
        MemoryNote(
            id: "\(scope.rawValue):\(relativePath)",
            scope: scope,
            title: "Preference",
            content: "Prefer small reviewable commits.",
            relativePath: relativePath,
            byteCount: 32
        )
    }
}
