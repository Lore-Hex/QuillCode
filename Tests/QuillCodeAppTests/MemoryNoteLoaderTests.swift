import XCTest
@testable import QuillCodeApp

final class MemoryNoteLoaderTests: XCTestCase {
    func testBoundsFilesAndRejectsSymlinkEscape() throws {
        let root = try makeQuillCodeTestDirectory()
        let outside = try makeQuillCodeTestDirectory().appendingPathComponent("outside.md")
        try "outside memory\n".write(to: outside, atomically: true, encoding: .utf8)
        let memoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: memoryDirectory.appendingPathComponent("outside.md"),
            withDestinationURL: outside
        )
        try String(repeating: "x", count: 64).write(
            to: memoryDirectory.appendingPathComponent("one.md"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored binary".write(
            to: memoryDirectory.appendingPathComponent("ignored.bin"),
            atomically: true,
            encoding: .utf8
        )

        let notes = MemoryNoteLoader.loadProject(
            from: root,
            maxNotes: 1,
            maxFileBytes: 12,
            maxTotalBytes: 12
        )

        XCTAssertEqual(notes.map(\.relativePath), [".quillcode/memories/one.md"])
        XCTAssertTrue(notes[0].wasTruncated)
        XCTAssertTrue(notes[0].content.contains("truncated"))
        XCTAssertFalse(notes[0].content.contains("outside memory"))
    }

    func testUpdateProjectRewritesExistingMemoryInsideProjectDirectory() throws {
        let root = try makeQuillCodeTestDirectory()
        let memoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try "Use SwiftPM.\n".write(
            to: memoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )
        let note = try XCTUnwrap(MemoryNoteLoader.loadProject(from: root).first)

        let updated = try MemoryNoteLoader.updateProject(
            id: note.id,
            content: "Use SwiftPM and keep slices small.",
            in: root
        )

        XCTAssertEqual(updated.id, note.id)
        XCTAssertEqual(updated.content, "Use SwiftPM and keep slices small.")
        XCTAssertEqual(updated.relativePath, ".quillcode/memories/project.md")
        XCTAssertEqual(
            try String(contentsOf: memoryDirectory.appendingPathComponent("project.md"), encoding: .utf8),
            "Use SwiftPM and keep slices small.\n"
        )
    }
}
