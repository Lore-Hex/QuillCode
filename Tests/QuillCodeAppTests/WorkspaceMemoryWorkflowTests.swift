import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceMemoryWorkflowTests: XCTestCase {
    func testScopeAndEditableNoteRespectMemoryIDPrefix() {
        let global = MemoryNote(
            id: "global:preferences.md",
            scope: .global,
            title: "Preferences",
            content: "Prefer concise answers.",
            relativePath: "memories/preferences.md",
            byteCount: 23
        )
        let project = MemoryNote(
            id: "project:.quillcode/memories/project.md",
            scope: .project,
            title: "Project",
            content: "Use SwiftUI.",
            relativePath: ".quillcode/memories/project.md",
            byteCount: 12
        )
        let projectRef = ProjectRef(name: "App", path: "/tmp/app", memories: [project])

        XCTAssertEqual(WorkspaceMemoryWorkflow.scope(for: global.id), .global)
        XCTAssertEqual(WorkspaceMemoryWorkflow.scope(for: project.id), .project)
        XCTAssertEqual(
            WorkspaceMemoryWorkflow.editableNote(id: global.id, globalMemories: [global], project: projectRef),
            global
        )
        XCTAssertEqual(
            WorkspaceMemoryWorkflow.editableNote(id: project.id, globalMemories: [global], project: projectRef),
            project
        )
    }

    func testDeleteRoutesGlobalMemoryThroughGlobalDirectory() throws {
        let globalDirectory = try makeQuillCodeTestDirectory()
        let note = try MemoryNoteLoader.saveGlobal(content: "Prefer small PRs.", to: globalDirectory)
        let context = WorkspaceMemoryWorkflowContext(
            globalMemoryDirectory: globalDirectory,
            editableProject: nil,
            editableProjectRoot: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let mutation = try XCTUnwrap(WorkspaceMemoryWorkflow.delete(id: note.id, context: context))

        XCTAssertEqual(mutation.updatedGlobalMemories, [])
        XCTAssertNil(mutation.updatedProjectMemories)
        XCTAssertEqual(mutation.noticeSummary, "Forgot memory: \(note.title)")
        XCTAssertEqual(MemoryNoteLoader.loadGlobal(from: globalDirectory), [])
    }

    func testUpdateRoutesLocalProjectMemoryThroughProjectRoot() throws {
        let projectRoot = try makeQuillCodeTestDirectory()
        let memoryDirectory = projectRoot.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        let memoryURL = memoryDirectory.appendingPathComponent("project.md")
        try "Use SwiftPM.\n".write(to: memoryURL, atomically: true, encoding: .utf8)
        let note = try XCTUnwrap(MemoryNoteLoader.loadProject(from: projectRoot).first)
        let context = WorkspaceMemoryWorkflowContext(
            globalMemoryDirectory: nil,
            editableProject: ProjectRef(name: "App", path: projectRoot.path, memories: [note]),
            editableProjectRoot: projectRoot,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let mutation = WorkspaceMemoryWorkflow.update(
            id: note.id,
            content: "Use SwiftPM and small reviewable changes.",
            userText: "/remember-edit \(note.id)\nUse SwiftPM and small reviewable changes.",
            context: context
        )

        XCTAssertNil(mutation.updatedGlobalMemories)
        XCTAssertEqual(mutation.updatedProjectMemories?.first?.content, "Use SwiftPM and small reviewable changes.")
        XCTAssertEqual(
            try String(contentsOf: memoryURL, encoding: .utf8),
            "Use SwiftPM and small reviewable changes.\n"
        )
    }
}
