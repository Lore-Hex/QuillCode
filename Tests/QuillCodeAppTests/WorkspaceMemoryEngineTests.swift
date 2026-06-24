import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceMemoryEngineTests: XCTestCase {
    func testSaveGlobalReturnsTranscriptRefreshAndNotice() throws {
        let directory = try temporaryDirectory()

        let mutation = WorkspaceMemoryEngine.saveGlobal(
            content: "Prefer small reviewable commits",
            userText: "/remember Prefer small reviewable commits",
            directory: directory
        )

        let memory = try XCTUnwrap(mutation.updatedGlobalMemories?.first)
        XCTAssertEqual(mutation.transcript.userText, "/remember Prefer small reviewable commits")
        XCTAssertEqual(mutation.transcript.title, "Memory: \(memory.title)")
        XCTAssertEqual(mutation.noticeSummary, "Saved memory: \(memory.title)")
        XCTAssertEqual(mutation.noticeRelativePath, memory.relativePath)
        XCTAssertTrue(mutation.changedContext)
        XCTAssertEqual(memory.content, "Prefer small reviewable commits")
    }

    func testSaveGlobalUnavailableReturnsFailureWithoutContextChange() {
        let mutation = WorkspaceMemoryEngine.saveGlobal(
            content: "Prefer small reviewable commits",
            userText: "/remember Prefer small reviewable commits",
            directory: nil
        )

        XCTAssertEqual(mutation.transcript.title, "Memory not saved")
        XCTAssertTrue(mutation.transcript.assistantText.contains("unavailable"))
        XCTAssertNil(mutation.updatedGlobalMemories)
        XCTAssertNil(mutation.noticeSummary)
        XCTAssertFalse(mutation.changedContext)
    }

    func testDeleteGlobalReturnsTranscriptRefreshAndNotice() throws {
        let directory = try temporaryDirectory()
        let note = try MemoryNoteLoader.saveGlobal(content: "Prefer concise answers", to: directory)

        let mutation = try XCTUnwrap(WorkspaceMemoryEngine.deleteGlobal(id: note.id, directory: directory))

        XCTAssertEqual(mutation.transcript.userText, "Forget memory: \(note.title)")
        XCTAssertEqual(mutation.transcript.title, "Forgot memory: \(note.title)")
        XCTAssertEqual(mutation.updatedGlobalMemories, [])
        XCTAssertEqual(mutation.noticeSummary, "Forgot memory: \(note.title)")
        XCTAssertEqual(mutation.noticeRelativePath, note.relativePath)
        let filename = note.relativePath.replacingOccurrences(of: "memories/", with: "")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(filename).path
        ))
        XCTAssertEqual(MemoryNoteLoader.loadGlobal(from: directory), [])
    }

    func testDeleteUnknownGlobalRefreshesAndReturnsFailureTranscript() throws {
        let directory = try temporaryDirectory()
        _ = try MemoryNoteLoader.saveGlobal(content: "Prefer concise answers", to: directory)

        let mutation = try XCTUnwrap(WorkspaceMemoryEngine.deleteGlobal(id: "missing-memory", directory: directory))

        XCTAssertEqual(mutation.transcript.title, "Memory not deleted")
        XCTAssertTrue(mutation.transcript.assistantText.contains("not found"))
        XCTAssertEqual(mutation.updatedGlobalMemories?.count, 1)
        XCTAssertFalse(mutation.changedContext)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
