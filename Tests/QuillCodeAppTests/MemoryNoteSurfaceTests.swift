import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class MemoryNoteSurfaceTests: XCTestCase {
    func testGlobalMemoryBuildsPreviewAndDeleteAction() {
        let note = MemoryNote(
            id: "global-1",
            scope: .global,
            title: "Preferences",
            content: String(repeating: "Prefer small reviewable changes. ", count: 12),
            relativePath: "memories/preferences.md",
            byteCount: 420,
            wasTruncated: true
        )

        let surface = MemoryNoteSurface(note: note)

        XCTAssertEqual(surface.id, "global-1")
        XCTAssertEqual(surface.scopeLabel, "Global")
        XCTAssertEqual(surface.title, "Preferences")
        XCTAssertEqual(surface.relativePath, "memories/preferences.md")
        XCTAssertEqual(surface.byteCountLabel, "420 bytes, truncated")
        XCTAssertTrue(surface.preview.hasSuffix("..."))
        XCTAssertLessThanOrEqual(surface.preview.count, 183)
        XCTAssertTrue(surface.canEdit)
        XCTAssertEqual(surface.editCommandID, "memory-edit:global-1")
        XCTAssertTrue(surface.canDelete)
        XCTAssertEqual(surface.deleteCommandID, "memory-delete:global-1")
    }

    func testProjectMemoryNormalizesMultilinePreviewWithoutDeleteAction() {
        let note = MemoryNote(
            id: "project-1",
            scope: .project,
            title: "Repo note",
            content: "\n\nUse SwiftPM.\n\nKeep slices small.\n",
            relativePath: ".quillcode/memories/repo.md",
            byteCount: 32
        )

        let surface = MemoryNoteSurface(note: note)

        XCTAssertEqual(surface.scopeLabel, "Project")
        XCTAssertEqual(surface.preview, "Use SwiftPM. Keep slices small.")
        XCTAssertEqual(surface.byteCountLabel, "32 bytes")
        XCTAssertFalse(surface.canEdit)
        XCTAssertNil(surface.editCommandID)
        XCTAssertFalse(surface.canDelete)
        XCTAssertNil(surface.deleteCommandID)
    }

    func testProjectMemoryCanExposeEditAndDeleteActionsWhenProjectOwnsIt() {
        let note = MemoryNote(
            id: "project:.quillcode/memories/repo.md",
            scope: .project,
            title: "Repo note",
            content: "Use SwiftPM.",
            relativePath: ".quillcode/memories/repo.md",
            byteCount: 12
        )

        let surface = MemoryNoteSurface(note: note, canEditProjectMemory: true)

        XCTAssertTrue(surface.canEdit)
        XCTAssertEqual(surface.editCommandID, "memory-edit:project:.quillcode/memories/repo.md")
        XCTAssertTrue(surface.canDelete)
        XCTAssertEqual(surface.deleteCommandID, "memory-delete:project:.quillcode/memories/repo.md")
    }
}
