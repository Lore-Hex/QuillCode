import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceMemoryEngineTests: XCTestCase {
    func testSaveGlobalReturnsTranscriptRefreshAndNotice() throws {
        let directory = try makeQuillCodeTestDirectory()

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

    func testSaveGlobalSensitiveContentRedactsTranscriptAndAddsReviewEvent() throws {
        let directory = try makeQuillCodeTestDirectory()

        let mutation = WorkspaceMemoryEngine.saveGlobal(
            content: "api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE",
            userText: "/remember api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE",
            directory: directory
        )

        XCTAssertEqual(mutation.transcript.title, "Memory not saved")
        XCTAssertTrue(mutation.transcript.userText.contains(ToolCall.redactedMemoryContentValue))
        XCTAssertFalse(mutation.transcript.userText.contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE"))
        let event = try XCTUnwrap(mutation.reviewEvent)
        XCTAssertEqual(event.kind, .notice)
        XCTAssertEqual(event.summary, MemoryRedactionReviewPayload.eventSummary)
        let payloadJSON = try XCTUnwrap(event.payloadJSON)
        XCTAssertTrue(payloadJSON.contains(ToolCall.redactedMemoryContentValue))
        XCTAssertFalse(payloadJSON.contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE"))
        XCTAssertEqual(mutation.updatedGlobalMemories, [])
        XCTAssertFalse(mutation.changedContext)
    }

    func testDeleteGlobalReturnsTranscriptRefreshAndNotice() throws {
        let directory = try makeQuillCodeTestDirectory()
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

    func testDeleteProjectReturnsTranscriptRefreshAndNotice() throws {
        let projectRoot = try makeQuillCodeTestDirectory()
        let memoryDirectory = projectRoot.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try "Use SwiftUI.\n".write(
            to: memoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )
        let note = try XCTUnwrap(MemoryNoteLoader.loadProject(from: projectRoot).first)

        let mutation = WorkspaceMemoryEngine.deleteProject(id: note.id, projectRoot: projectRoot)

        XCTAssertEqual(mutation.transcript.userText, "Forget memory: \(note.title)")
        XCTAssertEqual(mutation.transcript.title, "Forgot memory: \(note.title)")
        XCTAssertNil(mutation.updatedGlobalMemories)
        XCTAssertEqual(mutation.updatedProjectMemories, [])
        XCTAssertEqual(mutation.noticeSummary, "Forgot memory: \(note.title)")
        XCTAssertEqual(mutation.noticeRelativePath, note.relativePath)
        XCTAssertTrue(mutation.changedContext)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: memoryDirectory.appendingPathComponent("project.md").path
        ))
    }

    func testUpdateGlobalRewritesExistingMemoryAndReturnsNotice() throws {
        let directory = try makeQuillCodeTestDirectory()
        let note = try MemoryNoteLoader.saveGlobal(content: "Prefer concise answers", to: directory)

        let mutation = WorkspaceMemoryEngine.updateGlobal(
            id: note.id,
            content: "Prefer small reviewable commits",
            userText: "/remember-edit \(note.id)\nPrefer small reviewable commits",
            directory: directory
        )

        let updated = try XCTUnwrap(mutation.updatedGlobalMemories?.first)
        XCTAssertEqual(updated.id, note.id)
        XCTAssertEqual(updated.content, "Prefer small reviewable commits")
        XCTAssertEqual(mutation.transcript.title, "Updated memory: \(updated.title)")
        XCTAssertEqual(mutation.noticeSummary, "Updated memory: \(updated.title)")
        XCTAssertEqual(mutation.noticeRelativePath, updated.relativePath)
        XCTAssertTrue(mutation.changedContext)
        let filename = note.relativePath.replacingOccurrences(of: "memories/", with: "")
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8),
            "Prefer small reviewable commits\n"
        )
    }

    func testUpdateProjectRewritesExistingMemoryAndReturnsNotice() throws {
        let projectRoot = try makeQuillCodeTestDirectory()
        let memoryDirectory = projectRoot.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try "Use SwiftUI.\n".write(
            to: memoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )
        let note = try XCTUnwrap(MemoryNoteLoader.loadProject(from: projectRoot).first)

        let mutation = WorkspaceMemoryEngine.updateProject(
            id: note.id,
            content: "Use SwiftUI and keep UI state deterministic.",
            userText: "/remember-edit \(note.id)\nUse SwiftUI and keep UI state deterministic.",
            projectRoot: projectRoot
        )

        let updated = try XCTUnwrap(mutation.updatedProjectMemories?.first)
        XCTAssertNil(mutation.updatedGlobalMemories)
        XCTAssertEqual(updated.id, note.id)
        XCTAssertEqual(updated.content, "Use SwiftUI and keep UI state deterministic.")
        XCTAssertEqual(mutation.transcript.title, "Updated memory: \(updated.title)")
        XCTAssertEqual(mutation.noticeSummary, "Updated memory: \(updated.title)")
        XCTAssertEqual(mutation.noticeRelativePath, updated.relativePath)
        XCTAssertTrue(mutation.changedContext)
        XCTAssertEqual(
            try String(contentsOf: memoryDirectory.appendingPathComponent("project.md"), encoding: .utf8),
            "Use SwiftUI and keep UI state deterministic.\n"
        )
    }

    func testUpdateUnknownGlobalReturnsFailureWithoutContextChange() throws {
        let directory = try makeQuillCodeTestDirectory()
        _ = try MemoryNoteLoader.saveGlobal(content: "Prefer concise answers", to: directory)

        let mutation = WorkspaceMemoryEngine.updateGlobal(
            id: "missing-memory",
            content: "Prefer small reviewable commits",
            userText: "/remember-edit missing-memory\nPrefer small reviewable commits",
            directory: directory
        )

        XCTAssertEqual(mutation.transcript.title, "Memory not updated")
        XCTAssertTrue(mutation.transcript.assistantText.contains("not found"))
        XCTAssertEqual(mutation.updatedGlobalMemories?.count, 1)
        XCTAssertFalse(mutation.changedContext)
    }

    func testDeleteUnknownGlobalRefreshesAndReturnsFailureTranscript() throws {
        let directory = try makeQuillCodeTestDirectory()
        _ = try MemoryNoteLoader.saveGlobal(content: "Prefer concise answers", to: directory)

        let mutation = try XCTUnwrap(WorkspaceMemoryEngine.deleteGlobal(id: "missing-memory", directory: directory))

        XCTAssertEqual(mutation.transcript.title, "Memory not deleted")
        XCTAssertTrue(mutation.transcript.assistantText.contains("not found"))
        XCTAssertEqual(mutation.updatedGlobalMemories?.count, 1)
        XCTAssertFalse(mutation.changedContext)
    }
}
