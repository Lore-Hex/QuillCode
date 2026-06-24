import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceProjectContextRefresherTests: XCTestCase {
    func testRefreshLocalProjectMetadataReloadsGlobalAndProjectContext() throws {
        let projectRoot = try makeQuillCodeTestDirectory()
        let globalMemoryDirectory = projectRoot.appendingPathComponent("global-memories")
        let projectMemoryDirectory = projectRoot.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: globalMemoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "Prefer focused Swift tests.\n".write(
            to: projectRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Global preference.\n".write(
            to: globalMemoryDirectory.appendingPathComponent("global.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Project preference.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let projectID = UUID()
        var projects = [
            ProjectRef(id: projectID, name: "Project", path: projectRoot.path)
        ]
        let globalMemories = WorkspaceProjectContextRefresher.globalMemories(directory: globalMemoryDirectory)

        WorkspaceProjectContextRefresher.refreshLocalProjectMetadata(
            projectID: projectID,
            projects: &projects
        )

        XCTAssertEqual(globalMemories.map(\.title), ["Global"])
        XCTAssertEqual(projects.first?.instructions.map(\.path), ["AGENTS.md"])
        XCTAssertEqual(projects.first?.memories.map(\.title), ["Project"])

        let snapshot = WorkspaceProjectContextRefresher.threadContext(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        )
        XCTAssertEqual(snapshot.instructions.map(\.title), ["Project AGENTS.md"])
        XCTAssertEqual(snapshot.memories.map(\.title), ["Global", "Project"])
    }

    func testThreadContextSyncUsesThreadProjectBeforeFallback() {
        let fallbackProjectID = UUID()
        let threadProjectID = UUID()
        let projects = [
            Self.project(id: fallbackProjectID, instructionTitle: "Fallback instruction", memoryTitle: "Fallback memory"),
            Self.project(id: threadProjectID, instructionTitle: "Thread instruction", memoryTitle: "Thread memory")
        ]
        let globalMemories = [
            Self.memory(id: "global", scope: .global, title: "Global memory")
        ]
        var thread = ChatThread(title: "Thread", projectID: threadProjectID)

        WorkspaceProjectContextRefresher.syncThreadContext(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )

        XCTAssertEqual(thread.instructions.map(\.title), ["Thread instruction"])
        XCTAssertEqual(thread.memories.map(\.title), ["Global memory", "Thread memory"])

        WorkspaceProjectContextRefresher.syncThreadMemories(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: []
        )
        XCTAssertEqual(thread.instructions.map(\.title), ["Thread instruction"])
        XCTAssertEqual(thread.memories.map(\.title), ["Thread memory"])
    }

    private static func project(id: UUID, instructionTitle: String, memoryTitle: String) -> ProjectRef {
        ProjectRef(
            id: id,
            name: instructionTitle,
            path: "/tmp/\(id.uuidString)",
            instructions: [
                ProjectInstruction(
                    path: "\(instructionTitle).md",
                    title: instructionTitle,
                    content: instructionTitle,
                    byteCount: instructionTitle.utf8.count
                )
            ],
            memories: [
                memory(id: memoryTitle, scope: .project, title: memoryTitle)
            ]
        )
    }

    private static func memory(id: String, scope: MemoryScope, title: String) -> MemoryNote {
        MemoryNote(
            id: id,
            scope: scope,
            title: title,
            content: title,
            relativePath: "\(scope.rawValue)/\(id).md",
            byteCount: title.utf8.count
        )
    }
}
