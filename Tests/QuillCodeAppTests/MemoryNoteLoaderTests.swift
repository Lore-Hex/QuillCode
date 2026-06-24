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
}
